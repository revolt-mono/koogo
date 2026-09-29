import Observation

/// A quick action scans for targets, acts on them when asked, and rescans once the action finishes.
@MainActor
@Observable
final class QuickActionModel<Targets: Sendable> {
    enum Phase {
        case scanning
        /// The scan found nothing to act on.
        case idle
        case ready(Targets)
        case performing(Targets)
        case failed(String)
    }

    private(set) var phase = Phase.scanning
    private let scan: @Sendable () async throws -> Targets?
    private let action: @Sendable (Targets) async throws -> Void
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(
        scan: @escaping @Sendable () async throws -> Targets?,
        perform action: @escaping @Sendable (Targets) async throws -> Void
    ) {
        self.scan = scan
        self.action = action
    }

    /// Starts a scan, replacing one in flight. Ignored while the action runs, since a rescan follows it anyway.
    func refresh() {
        if case .performing = phase {
            return
        }
        startScan()
    }

    /// Stops the scan in flight, keeping the phase as it is.
    func cancel() {
        scanTask?.cancel()
    }

    /// Runs the action on the ready targets, then rescans; a no-op in any other phase. The action never cancels.
    func perform() {
        guard case .ready(let targets) = phase else {
            return
        }
        phase = .performing(targets)
        Task {
            do {
                try await action(targets)
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            startScan()
        }
    }

    private func startScan() {
        scanTask?.cancel()
        phase = .scanning
        scanTask = Task {
            let result = await Result { try await scan() }
            guard !Task.isCancelled else {
                return
            }
            phase =
                switch result {
                case .success(let targets): targets.map(Phase.ready) ?? .idle
                case .failure(let error): .failed(error.localizedDescription)
                }
        }
    }
}

extension QuickActionModel where Targets == Void {
    /// An action with nothing to scan for, such as a toggle: ready from the start and again once it finishes.
    convenience init(perform action: @escaping @Sendable () async throws -> Void) {
        self.init(scan: { () }, perform: { try await action() })
        phase = .ready(())
    }
}

extension QuickActionModel.Phase: Equatable where Targets: Equatable {}
