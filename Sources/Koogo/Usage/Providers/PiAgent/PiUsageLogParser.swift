import Foundation

private enum PiRecordKind: String, LogRecordKind {
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

struct PiLogParser: UsageLogParser {
    private var thinkingByEntry: [String: String] = [:]

    mutating func parse(
        _ line: Data,
        decoder: JSONDecoder
    ) -> UsageLineOutcome? {
        guard let record = try? decoder.decode(PiLogRecord.self, from: line) else {
            return nil
        }

        let thinking =
            switch record.action {
            case .thinking(let level): level
            case .inherit, .billed: record.parentID.flatMap { thinkingByEntry[$0] }
            }
        if let thinking {
            thinkingByEntry[record.id] = thinking
        }
        guard
            case .billed(let billedUsage, let model, let timestampSource) = record.action,
            model != nil || billedUsage.processedTokens > 0 || billedUsage.costUSD > 0
        else {
            return nil
        }
        let timestamp =
            switch timestampSource {
            case .entry: parseUsageTimestamp(record.timestamp)
            case .milliseconds(let milliseconds):
                Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
            }
        guard let timestamp else {
            return nil
        }

        return .event(
            .piAgent(
                entryID: record.id,
                usage: UsageRecord(
                    timestamp: timestamp,
                    processedTokens: billedUsage.processedTokens,
                    costUSD: billedUsage.costUSD,
                    modelTurn: model.map {
                        UsageRecord.ModelTurn(model: $0, reasoningEffort: thinking)
                    }
                )
            )
        )
    }
}

private struct PiLogRecord: Decodable {
    enum Action: Decodable {
        enum TimestampSource {
            case entry
            case milliseconds(UInt64)
        }

        case inherit
        case thinking(String)
        case billed(usage: PiLoggedUsage, model: UsageModelReference?, timestamp: TimestampSource)

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
            let model: UsageModelReference?
            switch role {
            case .assistant:
                model = .piAgent(
                    provider: try container.decode(String.self, forKey: .provider),
                    id: try container.decode(String.self, forKey: .model)
                )
            case .toolResult:
                model = nil
            case .other:
                self = .inherit
                return
            }
            self = .billed(
                usage: usage,
                model: model,
                timestamp: .milliseconds(try container.decode(UInt64.self, forKey: .timestamp))
            )
        }
    }

    let id: String
    let parentID: String?
    let timestamp: String
    let action: Action

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
        id = try container.decode(String.self, forKey: .id)
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        action =
            switch try container.decode(PiRecordKind.self, forKey: .type) {
            case .message:
                try container.decode(Action.self, forKey: .message)
            case .thinkingLevelChange:
                .thinking(try container.decode(String.self, forKey: .thinkingLevel))
            case .compaction, .branchSummary:
                try container.decodeIfPresent(PiLoggedUsage.self, forKey: .usage)
                    .map { .billed(usage: $0, model: nil, timestamp: .entry) }
                    ?? .inherit
            case .other:
                .inherit
            }
    }
}

private struct PiLoggedUsage: Decodable {
    let processedTokens: UInt64
    let costUSD: Decimal

    private enum CodingKeys: String, CodingKey {
        case totalTokens
        case cost
    }

    private enum CostCodingKeys: String, CodingKey {
        case total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        processedTokens = try container.decode(UInt64.self, forKey: .totalTokens)
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
        self.costUSD = costUSD
    }
}
