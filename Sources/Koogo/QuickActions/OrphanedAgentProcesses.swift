import Darwin
import Foundation

/// agent processes without a driving terminal session: daemons, pty hosts, spares, and closed-terminal leftovers.
struct OrphanedAgentProcess: Sendable {
    static let providers = Provider.allCases.filter { $0.ownsProcess != nil }

    fileprivate let identity: ProcessIdentity
    let provider: Provider

    init?(_ identity: ProcessIdentity, parentPID: pid_t, hasTerminal: Bool, executablePath: String) {
        guard
            !hasTerminal,
            parentPID != ProcessInfo.processInfo.processIdentifier,
            case let executable = URL(filePath: executablePath),
            let provider = Self.providers.first(where: { $0.ownsProcess?(executable) == true })
        else { return nil }
        self.identity = identity
        self.provider = provider
    }
}

private extension Provider {
    var ownsProcess: ((URL) -> Bool)? {
        switch self {
        case .codex: { $0.lastPathComponent == "codex" }
        case .claude:
            { $0.lastPathComponent.wholeMatch(of: /\d+\.\d+\.\d+/) != nil && $0.pathComponents.contains("claude") }
        case .piAgent: nil
        case .grok: { $0.lastPathComponent.hasPrefix("grok") }
        }
    }
}

struct OrphanedAgentProcesses: Sendable {
    enum Failure: LocalizedError {
        case scan
        case termination(OrphanedAgentProcess)

        var errorDescription: String? {
            switch self {
            case .scan:
                "Could not list running processes."
            case .termination(let process):
                "Could not stop \(process.provider.title) process \(process.identity.pid)."
            }
        }
    }

    let values: [OrphanedAgentProcess]

    init?(_ processes: [OrphanedAgentProcess]) {
        guard !processes.isEmpty else {
            return nil
        }
        values = processes
    }

    var summary: String {
        OrphanedAgentProcess.providers.compactMap { provider in
            let count = values.count { $0.provider == provider }
            return count > 0 ? "\(count) \(provider.title.lowercased())" : nil
        }
        .joined(separator: ", ")
    }

    @concurrent
    static func running() async throws -> OrphanedAgentProcesses? {
        guard let pids = LibProc.currentUserPIDs() else { throw Failure.scan }
        return OrphanedAgentProcesses(pids.compactMap(orphanedAgentProcess))
    }

    private static func orphanedAgentProcess(_ pid: pid_t) -> OrphanedAgentProcess? {
        guard
            let info = LibProc.bsdInfo(of: pid),
            let executablePath = LibProc.executablePath(of: pid),
            let identity = LibProc.identity(of: pid)
        else { return nil }
        return OrphanedAgentProcess(
            identity,
            parentPID: info.parentPID,
            hasTerminal: info.hasTerminal,
            executablePath: executablePath
        )
    }

    func forceTerminate() throws {
        var survivor: OrphanedAgentProcess?
        for process in values {
            do {
                try LibProc.forceKill(process.identity)
            } catch {
                survivor = survivor ?? process
            }
        }
        if let survivor {
            throw Failure.termination(survivor)
        }
    }
}
