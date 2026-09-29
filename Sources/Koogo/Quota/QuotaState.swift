/// What a quota section shows: nothing fetched yet, no quota and why, or the latest snapshot,
/// marked stale with the reason its latest refresh failed.
enum QuotaState: Equatable {
    case loading
    case unavailable(QuotaUnavailability)
    case available(QuotaSnapshot, stale: QuotaUnavailability?)

    var snapshot: QuotaSnapshot? {
        guard case .available(let snapshot, _) = self else { return nil }
        return snapshot
    }

    /// A failure keeps an earlier snapshot, marked stale, instead of hiding it.
    mutating func apply(_ result: Result<QuotaSnapshot, QuotaUnavailability>) {
        switch result {
        case .success(let snapshot):
            self = .available(snapshot, stale: nil)
        case .failure(let reason):
            self = snapshot.map { .available($0, stale: reason) } ?? .unavailable(reason)
        }
    }
}
