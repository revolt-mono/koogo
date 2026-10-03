import Darwin
import Foundation
import Synchronization

final class ProcessGroupLifetime: Sendable {
    private enum State {
        case pending
        case running(Process)
        case terminating(Process)
        case stopped
    }

    private let state = Mutex(State.pending)

    static func run<Value: Sendable>(
        timeout: Duration,
        _ operation: @escaping @Sendable (ProcessGroupLifetime) throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                let processGroup = ProcessGroupLifetime()
                return try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        DispatchQueue.global(qos: .utility).async {
                            continuation.resume(with: Result { try operation(processGroup) })
                        }
                    }
                } onCancel: {
                    processGroup.terminate()
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CommandLineTool.Failure.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    func start(_ process: Process) throws {
        try state.withLock { state in
            switch state {
            case .pending:
                try process.run()
                guard getpgid(process.processIdentifier) == process.processIdentifier else {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                    throw CocoaError(.executableLoad)
                }
                state = .running(process)
            case .stopped:
                throw CancellationError()
            case .running, .terminating:
                preconditionFailure("process group lifetime cannot start twice")
            }
        }
    }

    func finish() {
        state.withLock { state in
            if case .terminating(let process) = state,
                Self.processGroupExists(process.processIdentifier)
            {
                return
            }
            state = .stopped
        }
    }

    func terminate() {
        let process = state.withLock { state -> Process? in
            switch state {
            case .pending:
                state = .stopped
                return nil
            case .running(let process) where Self.processGroupExists(process.processIdentifier):
                state = .terminating(process)
                return process
            case .running:
                state = .stopped
                return nil
            case .terminating, .stopped:
                return nil
            }
        }
        guard let process else {
            return
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGTERM)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            self.forceTerminate()
        }
    }

    private func forceTerminate() {
        guard
            let process = state.withLock({ state -> Process? in
                guard case .terminating(let process) = state else {
                    return nil
                }
                state = .stopped
                return process
            })
        else {
            return
        }
        Darwin.kill(-process.processIdentifier, SIGKILL)
    }

    private static func processGroupExists(_ processGroupIdentifier: Int32) -> Bool {
        Darwin.kill(-processGroupIdentifier, 0) != -1 || errno != ESRCH
    }
}
