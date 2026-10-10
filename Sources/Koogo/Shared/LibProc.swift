import Darwin

enum LibProc {
    static func pids(ownedBy uid: uid_t? = nil) -> [pid_t]? {
        let type = UInt32(uid == nil ? PROC_ALL_PIDS : PROC_UID_ONLY)
        let pidStride = Int32(MemoryLayout<pid_t>.stride)
        let listedBytes = proc_listpids(type, uid ?? 0, nil, 0)
        guard listedBytes > 0 else { return nil }
        // Leave room for processes launched between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(listedBytes / pidStride) + 256)
        let filledBytes = proc_listpids(type, uid ?? 0, &pids, Int32(pids.count) * pidStride)
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
