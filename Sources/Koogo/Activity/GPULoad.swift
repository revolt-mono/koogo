import Darwin
import IOKit
import Metal

/// The accelerator's utilization and the system memory it holds, from the IOAccelerator performance statistics. Rendering and tiling are the two stages apple gpus report separately.
struct GPULoad: Equatable, Sendable {
    let name: String
    let utilization: Double
    let renderer: Double
    let tiler: Double
    let memory: UInt64

    /// The default device's registry id names its IOAccelerator entry, so a second gpu's statistics never wear its name.
    private static let device = MTLCreateSystemDefaultDevice().map { (name: $0.name, registryID: $0.registryID) }

    /// Nil when the machine exposes no accelerator statistics, which only means the gpu goes unshown.
    static func read() -> GPULoad? {
        guard let (name, registryID) = device else { return nil }
        var load: GPULoad?
        forEachAccelerator { accelerator in
            var entryID: UInt64 = 0
            guard
                load == nil, IORegistryEntryGetRegistryEntryID(accelerator, &entryID) == KERN_SUCCESS,
                entryID == registryID,
                let statistics = property(accelerator, "PerformanceStatistics") as? [String: Any],
                let utilization = statistics["Device Utilization %"] as? Double,
                let renderer = statistics["Renderer Utilization %"] as? Double,
                let tiler = statistics["Tiler Utilization %"] as? Double,
                let memory = statistics["In use system memory"] as? UInt64
            else { return }
            let fraction = { (percent: Double) in min(max(percent / 100, 0), 1) }
            load = GPULoad(
                name: name,
                utilization: fraction(utilization),
                renderer: fraction(renderer),
                tiler: fraction(tiler),
                memory: memory
            )
        }
        return load
    }

    /// Gpu time each process has accumulated across its accelerator clients, in the nanoseconds the driver reports.
    static func timePerProcess() -> [pid_t: Duration] {
        var times: [pid_t: Duration] = [:]
        forEachAccelerator { accelerator in
            var clients: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &clients) == KERN_SUCCESS else {
                return
            }
            defer { IOObjectRelease(clients) }
            while case let client = IOIteratorNext(clients), client != 0 {
                defer { IOObjectRelease(client) }
                guard
                    let creator = property(client, "IOUserClientCreator") as? String,
                    let pid = creator.split(separator: ",").first.flatMap({ pid_t($0.dropFirst("pid ".count)) }),
                    let usage = property(client, "AppUsage") as? [[String: Any]]
                else { continue }
                for queue in usage {
                    times[pid, default: .zero] += .nanoseconds(queue["accumulatedGPUTime"] as? UInt64 ?? 0)
                }
            }
        }
        return times
    }

    private static func forEachAccelerator(_ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
                == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }
        while case let accelerator = IOIteratorNext(iterator), accelerator != 0 {
            body(accelerator)
            IOObjectRelease(accelerator)
        }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
