import Darwin

enum Sysctl {
    /// Nil when the kernel has no such name, which is how an intel mac answers for performance levels.
    static func value<Value: FixedWidthInteger>(_ name: String) -> Value? {
        var value: Value = 0
        var size = MemoryLayout<Value>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 && size == MemoryLayout<Value>.size ? value : nil
    }
}

enum MachHost {
    /// Each `mach_host_self()` call adds a send right that is never released; one is enough.
    static let port = mach_host_self()
}
