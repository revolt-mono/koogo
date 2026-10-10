import Darwin
import Foundation

/// An agent process whose launching terminal is gone, so launchd now parents it.
struct OrphanedAgentProcess: Sendable {
    fileprivate let pid: pid_t
    let provider: Provider

    init?(pid: pid_t, parentPID: pid_t, executablePath: String) {
        guard parentPID == 1, let provider = Provider.allCases.first(where: { $0.ownsProcess(at: executablePath) })
        else { return nil }
        self.pid = pid
        self.provider = provider
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
                "Could not stop \(process.provider.rawValue) process \(process.pid)."
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
            return count > 0 ? "\(count) \(provider.rawValue)" : nil
        }
        .joined(separator: ", ")
    }

    @concurrent
    static func running() async throws -> OrphanedAgentProcesses? {
        guard let pids = LibProc.pids() else { throw Failure.scan }
        return OrphanedAgentProcesses(pids.compactMap(orphanedAgentProcess))
    }

    private static func orphanedAgentProcess(_ pid: pid_t) -> OrphanedAgentProcess? {
        var info = proc_bsdinfo()
        guard
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
            info.pbi_uid == getuid(),
            let executablePath = LibProc.executablePath(of: pid)
        else { return nil }
        return OrphanedAgentProcess(pid: pid, parentPID: pid_t(info.pbi_ppid), executablePath: executablePath)
    }

    @concurrent
    func terminate() async throws {
        // A pid can be reused between the scan and the click; only signal processes that still match.
        var survivors = values.filter { Self.orphanedAgentProcess($0.pid) != nil }
        for process in survivors {
            try Self.send(SIGTERM, to: process)
        }
        for _ in 0..<20 where !survivors.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
            survivors.removeAll { Darwin.kill($0.pid, 0) == -1 && (errno == ESRCH || errno == EPERM) }
        }
        for process in survivors {
            try Self.send(SIGKILL, to: process)
        }
    }

    private static func send(_ signal: Int32, to process: OrphanedAgentProcess) throws {
        guard Darwin.kill(process.pid, signal) == 0 || errno == ESRCH else {
            throw Failure.termination(process)
        }
    }
}
