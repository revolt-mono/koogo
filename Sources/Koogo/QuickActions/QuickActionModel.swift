import Observation

/// row-scoped; appearing starts a scan and disappearing cancels it, leaving `.scanning` until the next appearance. started actions finish and rescan after closure.
@MainActor
@Observable
final class QuickActionModel<Targets: Sendable> {
    enum Phase {
        case scanning
        case idle
        case ready(Targets)
        case performing(Targets)
        case scanFailed(String)
        case performFailed(String)
    }

    private enum Source {
        case fixed(Targets)
        case scan(@Sendable () async throws -> Targets?)
    }

    private(set) var phase: Phase
    private let source: Source
    private let action: @Sendable (Targets) async throws -> Void
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    convenience init(
        scan: @escaping @Sendable () async throws -> Targets?,
        perform action: @escaping @Sendable (Targets) async throws -> Void
    ) {
        self.init(source: .scan(scan), perform: action)
    }

    private init(source: Source, perform action: @escaping @Sendable (Targets) async throws -> Void) {
        self.source = source
        self.action = action
        phase =
            switch source {
            case .fixed(let targets): .ready(targets)
            case .scan: .scanning
            }
    }

    var activate: (@MainActor () -> Void)? {
        switch phase {
        case .ready: perform
        case .scanFailed, .performFailed: refresh
        case .scanning, .idle, .performing: nil
        }
    }

    func refresh() {
        if case .performing = phase {
            return
        }
        startScan()
    }

    func cancel() {
        scanTask?.cancel()
    }

    func perform() {
        guard case .ready(let targets) = phase else {
            return
        }
        phase = .performing(targets)
        Task {
            do {
                try await action(targets)
            } catch {
                phase = .performFailed(error.localizedDescription)
                return
            }
            startScan()
        }
    }

    private func startScan() {
        scanTask?.cancel()
        switch source {
        case .fixed(let targets):
            phase = .ready(targets)
        case .scan(let scan):
            phase = .scanning
            scanTask = Task {
                let result = await Result { try await scan() }
                guard !Task.isCancelled else {
                    return
                }
                phase =
                    switch result {
                    case .success(let targets): targets.map(Phase.ready) ?? .idle
                    case .failure(let error): .scanFailed(error.localizedDescription)
                    }
            }
        }
    }
}

extension QuickActionModel where Targets == Void {
    convenience init(perform action: @escaping @Sendable () async throws -> Void) {
        self.init(source: .fixed(()), perform: { try await action() })
    }
}

extension QuickActionModel.Phase: Equatable where Targets: Equatable {}
