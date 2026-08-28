import Foundation

private enum PiRecordKind: String, LogRecordKind {
    case session
    case message
    case thinkingLevelChange = "thinking_level_change"
    case compaction
    case branchSummary = "branch_summary"
    case other
}

private enum PiMessageRole: String, LogRecordKind {
    case assistant
    case toolResult
    case other
}

struct PiLogParser: Sendable {
    private var thinkingByEntry: [String: String] = [:]

    mutating func parse(
        _ line: Data,
        decoder: JSONDecoder
    ) -> UsageEvent? {
        guard let record = try? decoder.decode(PiLogRecord.self, from: line) else {
            return nil
        }
        guard case .entry(let entryID, let parentID, let timestampValue, let action) = record else {
            return nil
        }

        let thinking =
            switch action {
            case .thinking(let level): level
            case .inherit, .billed: parentID.flatMap { thinkingByEntry[$0] }
            }
        if let thinking {
            thinkingByEntry[entryID] = thinking
        }
        guard
            case .billed(let billedUsage, let model, let messageTimestamp) = action,
            model != nil || billedUsage.processedTokens > 0 || billedUsage.costUSD > 0
        else {
            return nil
        }
        let timestamp =
            messageTimestamp.map {
                Date(timeIntervalSince1970: TimeInterval($0) / 1_000)
            } ?? timestampValue.flatMap(parseUsageTimestamp)
        guard let timestamp else {
            return nil
        }

        return .piAgent(
            entryID: entryID,
            usage: UsageRecord(
                timestamp: timestamp,
                processedTokens: billedUsage.processedTokens,
                costUSD: billedUsage.costUSD,
                modelTurn: model.map {
                    UsageRecord.ModelTurn(
                        model: .piAgent(provider: $0.provider, id: $0.id),
                        reasoningEffort: thinking
                    )
                }
            )
        )
    }
}

private enum PiLogRecord: Decodable {
    enum Action: Decodable {
        case inherit
        case thinking(String)
        case billed(usage: PiLoggedUsage, model: PiModel?, timestampMilliseconds: Int64?)

        private enum CodingKeys: String, CodingKey {
            case role
            case provider
            case model
            case timestamp
            case usage
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let role = try container.decode(PiMessageRole.self, forKey: .role)
            guard let usage = try container.decodeIfPresent(PiLoggedUsage.self, forKey: .usage) else {
                self = .inherit
                return
            }
            let model: PiModel?
            switch role {
            case .assistant:
                model =
                    if let provider = nonempty(
                        try container.decodeIfPresent(String.self, forKey: .provider)
                    ),
                        let id = nonempty(try container.decodeIfPresent(String.self, forKey: .model))
                    {
                        PiModel(provider: provider, id: id)
                    } else {
                        nil
                    }
            case .toolResult:
                model = nil
            case .other:
                self = .inherit
                return
            }
            self = .billed(
                usage: usage,
                model: model,
                timestampMilliseconds: try container.decodeIfPresent(Int64.self, forKey: .timestamp)
            )
        }
    }

    case session
    case entry(id: String, parentID: String?, timestamp: String?, action: Action)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case parentID = "parentId"
        case timestamp
        case thinkingLevel
        case message
        case usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PiRecordKind.self, forKey: .type)
        guard type != .session else {
            self = .session
            return
        }
        let action: Action
        switch type {
        case .message:
            action =
                try container.decodeIfPresent(Action.self, forKey: .message)
                ?? .inherit
        case .thinkingLevelChange:
            action =
                try container.decodeIfPresent(String.self, forKey: .thinkingLevel)
                .flatMap(nonempty)
                .map(Action.thinking) ?? .inherit
        case .compaction, .branchSummary:
            action =
                try container.decodeIfPresent(PiLoggedUsage.self, forKey: .usage)
                .map { .billed(usage: $0, model: nil, timestampMilliseconds: nil) }
                ?? .inherit
        case .session, .other:
            action = .inherit
        }
        guard let id = nonempty(try container.decodeIfPresent(String.self, forKey: .id)) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "missing entry id"
            )
        }
        self = .entry(
            id: id,
            parentID: nonempty(try container.decodeIfPresent(String.self, forKey: .parentID)),
            timestamp: try container.decodeIfPresent(String.self, forKey: .timestamp),
            action: action
        )
    }
}

private struct PiModel {
    let provider: String
    let id: String
}

private struct PiLoggedUsage: Decodable {
    let processedTokens: Int64
    let costUSD: Decimal

    private enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead
        case cacheWrite
        case cost
    }

    private enum CostCodingKeys: String, CodingKey {
        case total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var processedTokens: Int64 = 0
        for tokenCount in [
            try container.decode(Int64.self, forKey: .input),
            try container.decode(Int64.self, forKey: .output),
            try container.decode(Int64.self, forKey: .cacheRead),
            try container.decode(Int64.self, forKey: .cacheWrite),
        ] {
            let (sum, overflow) = processedTokens.addingReportingOverflow(tokenCount)
            guard tokenCount >= 0, !overflow else {
                throw DecodingError.dataCorruptedError(
                    forKey: .input,
                    in: container,
                    debugDescription: "invalid token usage"
                )
            }
            processedTokens = sum
        }
        let costUSD = try container.nestedContainer(
            keyedBy: CostCodingKeys.self,
            forKey: .cost
        ).decode(Decimal.self, forKey: .total)
        guard costUSD >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .cost,
                in: container,
                debugDescription: "invalid usage cost"
            )
        }
        self.processedTokens = processedTokens
        self.costUSD = costUSD
    }
}
