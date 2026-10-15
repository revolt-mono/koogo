enum QuotaUnavailability: String, Encodable, Sendable {
    case binaryNotFound
    case timedOut
    /// the tool exited, never ran, or refused the request.
    case sessionFailed
    /// the tool answered with an unsupported message shape.
    case invalidMessage
    case emptyLimits
    /// the tool determined locally that plan limits do not apply, such as for an api key.
    case noPlan
}

enum QuotaReading: Equatable, Sendable {
    case available(QuotaSnapshot)
    case unavailable(QuotaUnavailability)

    init(_ snapshot: QuotaSnapshot?) {
        self = snapshot.map(Self.available) ?? .unavailable(.emptyLimits)
    }

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
