import Darwin

enum MachHost {
  /// each call to `mach_host_self()` adds a send right.
  static let port = mach_host_self()

  static func statistics<Info>(
    _ flavor: host_flavor_t,
    as empty: Info,
    from query: (host_t, host_flavor_t, host_info_t, UnsafeMutablePointer<mach_msg_type_number_t>) -> kern_return_t,
  ) -> Info? {
    var info = empty
    var count = mach_msg_type_number_t(MemoryLayout<Info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { query(port, flavor, $0, &count) }
    }
    return status == KERN_SUCCESS ? info : nil
  }
}
