import Darwin
import Foundation

/// agent processes without a driving terminal session: daemons, pty hosts, spares, and closed-terminal leftovers.
struct OrphanedAgentProcess: Sendable {
    /// the terminal device value for a process without a controlling terminal.
    static let noTerminal = UInt32.max

    fileprivate let identity: ProcessIdentity
    let provider: Provider

    init?(_ identity: ProcessIdentity, parentPID: pid_t, terminalDevice: UInt32, executablePath: String) {
        guard
            terminalDevice == Self.noTerminal,
            parentPID != ProcessInfo.processInfo.processIdentifier,
            let provider = Provider.allCases.first(where: { $0.ownsProcess(at: executablePath) })
        else { return nil }
        self.identity = identity
        self.provider = provider
    }
}

private extension Provider {
    func ownsProcess(at executablePath: String) -> Bool {
        let executable = URL(filePath: executablePath)
        let name = executable.lastPathComponent
        return switch self {
        case .codex: name == "codex"
        case .claude: name.wholeMatch(of: /\d+\.\d+\.\d+/) != nil && executable.pathComponents.contains("claude")
        case .piAgent: false
        case .grok: name.hasPrefix("grok")
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
        Provider.allCases.compactMap { provider in
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
        var info = proc_bsdinfo()
        guard
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
            let executablePath = LibProc.executablePath(of: pid),
            let identity = LibProc.identity(of: pid)
        else { return nil }
        return OrphanedAgentProcess(
            identity,
            parentPID: pid_t(info.pbi_ppid),
            terminalDevice: info.e_tdev,
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
