import Darwin

struct MemoryUsage: Sendable {
  let total: UInt64
  let app: UInt64
  let wired: UInt64
  let compressed: UInt64

  var used: UInt64 {
    app + wired + compressed
  }

  static func read() throws -> MemoryUsage {
    var pageSize: vm_size_t = 0
    guard
      let statistics = MachHost.statistics(HOST_VM_INFO64, as: vm_statistics64(), from: host_statistics64),
      host_page_size(MachHost.port, &pageSize) == KERN_SUCCESS,
      let total: UInt64 = Sysctl.value("hw.memsize")
    else { throw ActivityReadFailure.memory }
    let bytes = { (pages: UInt32) in UInt64(pages) * UInt64(pageSize) }
    return MemoryUsage(
      total: total,
      app: bytes(statistics.internal_page_count &- statistics.purgeable_count),
      wired: bytes(statistics.wire_count),
      compressed: bytes(statistics.compressor_page_count),
    )
  }
}
