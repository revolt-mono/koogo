/// What a quota section shows: nothing fetched yet, no quota and why, or the latest snapshot. The newest
/// read is the whole state, so a failed read hides the section until a read succeeds.
enum QuotaState: Equatable {
    case loading
    case unavailable(QuotaUnavailability)
    case available(QuotaSnapshot)

    var snapshot: QuotaSnapshot? {
        guard case .available(let snapshot) = self else { return nil }
        return snapshot
    }
}
