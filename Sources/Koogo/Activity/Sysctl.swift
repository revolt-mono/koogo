import Darwin

enum Sysctl {
    static func value<Value: FixedWidthInteger>(_ name: String) -> Value? {
        var value: Value = 0
        var size = MemoryLayout<Value>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 && size == MemoryLayout<Value>.size ? value : nil
    }
}

enum MachHost {
    /// each host-port query adds a send right; retain one port for the process lifetime.
    static let port = mach_host_self()
}
