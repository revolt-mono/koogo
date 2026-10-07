import Darwin

/// Physical memory split the way activity monitor shows it: app memory is internal pages less purgeable ones.
struct MemoryUsage: Equatable, Sendable {
    let total: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64

    var used: UInt64 { app + wired + compressed }

    static func read() throws -> MemoryUsage {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard status == KERN_SUCCESS, host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS,
            let total: UInt64 = Sysctl.value("hw.memsize")
        else { throw ActivityReadFailure.memory }
        let bytes = { (pages: UInt32) in UInt64(pages) * UInt64(pageSize) }
        return MemoryUsage(
            total: total,
            app: bytes(statistics.internal_page_count &- statistics.purgeable_count),
            wired: bytes(statistics.wire_count),
            compressed: bytes(statistics.compressor_page_count)
        )
    }
}
