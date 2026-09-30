import Darwin
import Foundation

struct OrphanedAgentProcess: Sendable {
    enum Agent: String, CaseIterable {
        case claude, codex, grok
    }

    fileprivate let pid: pid_t
    let agent: Agent

    init?(pid: pid_t, parentPID: pid_t, executablePath: String) {
        guard parentPID == 1 else { return nil }
        let executable = URL(filePath: executablePath)
        let name = executable.lastPathComponent
        if name == "codex" {
            agent = .codex
        } else if name.hasPrefix("grok") {
            agent = .grok
        } else if name.wholeMatch(of: /\d+\.\d+\.\d+/) != nil, executable.pathComponents.contains("claude") {
            agent = .claude
        } else {
            return nil
        }
        self.pid = pid
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
                "Could not stop \(process.agent.rawValue) process \(process.pid)."
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
        OrphanedAgentProcess.Agent.allCases.compactMap { agent in
            let count = values.count { $0.agent == agent }
            return count > 0 ? "\(count) \(agent.rawValue)" : nil
        }
        .joined(separator: ", ")
    }

    @concurrent
    static func running() async throws -> OrphanedAgentProcesses? {
        let pidStride = Int32(MemoryLayout<pid_t>.stride)
        let listedBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard listedBytes > 0 else { throw Failure.scan }
        // Leave room for processes launched between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(listedBytes / pidStride) + 256)
        let filledBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count) * pidStride)
        guard filledBytes > 0 else { throw Failure.scan }

        return OrphanedAgentProcesses(pids.prefix(Int(filledBytes / pidStride)).compactMap(orphanedAgentProcess))
    }

    private static func orphanedAgentProcess(_ pid: pid_t) -> OrphanedAgentProcess? {
        var info = proc_bsdinfo()
        guard
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
            info.pbi_uid == getuid()
        else { return nil }
        var path = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = Int(proc_pidpath(pid, &path, UInt32(path.count)))
        guard pathLength > 0, let executablePath = String(bytes: path.prefix(pathLength), encoding: .utf8) else {
            return nil
        }
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
