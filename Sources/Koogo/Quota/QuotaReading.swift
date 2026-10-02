enum QuotaUnavailability: String, Error, Encodable, Sendable {
    case binaryNotFound
    case timedOut
    case sessionFailed
    case emptyLimits

    init(_ error: any Error) {
        self =
            switch error {
            case CommandLineTool.Failure.notFound: .binaryNotFound
            case CommandLineTool.Failure.timedOut: .timedOut
            default: .sessionFailed
            }
    }
}

/// One answer from a provider's tool.
enum QuotaReading: Equatable, Sendable {
    case available(QuotaSnapshot)
    case unavailable(QuotaUnavailability)

    var snapshot: QuotaSnapshot? {
        guard case .available(let snapshot) = self else { return nil }
        return snapshot
    }
}

extension QuotaReading: Encodable {
    private enum CodingKeys: CodingKey {
        case state
        case reason
        case snapshot
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .available(let snapshot):
            try container.encode("available", forKey: .state)
            try container.encode(snapshot, forKey: .snapshot)
        case .unavailable(let reason):
            try container.encode("unavailable", forKey: .state)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// Where a provider's quota stands between reads. A cooldown exists only after an available reading.
enum QuotaStatus: Equatable, Sendable {
    case unread
    case reading(last: QuotaReading?)
    case read(QuotaReading, since: ContinuousClock.Instant)

    var latest: QuotaReading? {
        switch self {
        case .unread: nil
        case .reading(let last): last
        case .read(let reading, _): reading
        }
    }

    var isBusy: Bool {
        if case .reading = self { true } else { false }
    }

    func isFresh(at now: ContinuousClock.Instant, within cooldown: Duration) -> Bool {
        guard case .read(.available, let readAt) = self else { return false }
        return now < readAt + cooldown
    }
}
