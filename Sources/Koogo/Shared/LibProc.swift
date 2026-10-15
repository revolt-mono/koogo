import Darwin
import System

/// pairs a pid with launch time to distinguish reused process ids.
struct ProcessIdentity: Hashable, Sendable {
    let pid: pid_t
    /// process start time in mach absolute ticks.
    let startTicks: UInt64
}

enum LibProc {
    /// signals only the identified process; a missing or reused pid counts as already gone.
    static func forceKill(_ process: ProcessIdentity) throws(Errno) {
        guard identity(of: process.pid) == process else { return }
        guard Darwin.kill(process.pid, SIGKILL) == 0 || errno == ESRCH else { throw Errno(rawValue: errno) }
    }

    static func identity(of pid: pid_t) -> ProcessIdentity? {
        resourceUsage(of: pid).map { ProcessIdentity(pid: pid, startTicks: $0.ri_proc_start_abstime) }
    }

    static func currentUserPIDs() -> [pid_t]? {
        let type = UInt32(PROC_UID_ONLY)
        let uid = getuid()
        let pidStride = Int32(MemoryLayout<pid_t>.stride)
        let listedBytes = proc_listpids(type, uid, nil, 0)
        guard listedBytes > 0 else { return nil }
        // allow for processes launched between sizing and filling the pid buffer.
        var pids = [pid_t](repeating: 0, count: Int(listedBytes / pidStride) + 256)
        let filledBytes = proc_listpids(type, uid, &pids, Int32(pids.count) * pidStride)
        guard filledBytes > 0 else { return nil }
        pids.removeSubrange(Int(filledBytes / pidStride)...)
        return pids
    }

    static func executablePath(of pid: pid_t) -> String? {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: Int(MAXPATHLEN)) { path in
            let pathLength = Int(proc_pidpath(pid, path.baseAddress, UInt32(path.count)))
            return pathLength > 0 ? String(validating: path[..<pathLength], as: UTF8.self) : nil
        }
    }

    static func resourceUsage(of pid: pid_t) -> rusage_info_v4? {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return status == 0 ? usage : nil
    }
}
