enum QuotaUnavailability: String, Error, Encodable, Sendable {
    case binaryNotFound
    case timedOut
    case sessionFailed
    case emptyLimits
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
