enum QuotaState: Equatable {
    case loading
    case unavailable(QuotaUnavailability)
    case available(QuotaSnapshot)

    var snapshot: QuotaSnapshot? {
        guard case .available(let snapshot) = self else { return nil }
        return snapshot
    }
}
