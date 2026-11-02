import Darwin
import IOKit
import Metal

/// apple gpus report rendering and tiling as separate stages.
struct GPULoad: Sendable {
    let name: String
    let utilization: Double
    let renderer: Double
    let tiler: Double

    private static let device = MTLCreateSystemDefaultDevice().map { (name: $0.name, registryID: $0.registryID) }

    static func read() -> GPULoad? {
        guard let (name, registryID) = device else { return nil }
        let accelerator = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
        guard accelerator != 0 else { return nil }
        defer { IOObjectRelease(accelerator) }
        guard
            let statistics = property(accelerator, "PerformanceStatistics") as? [String: Any],
            let utilization = statistics["Device Utilization %"] as? Double,
            let renderer = statistics["Renderer Utilization %"] as? Double,
            let tiler = statistics["Tiler Utilization %"] as? Double
        else { return nil }
        let fraction = { (percent: Double) in min(max(percent / 100, 0), 1) }
        return GPULoad(
            name: name,
            utilization: fraction(utilization),
            renderer: fraction(renderer),
            tiler: fraction(tiler)
        )
    }

    static func timePerProcess() -> [pid_t: Duration] {
        var accelerators: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &accelerators)
                == KERN_SUCCESS
        else { return [:] }
        defer { IOObjectRelease(accelerators) }
        var times: [pid_t: Duration] = [:]
        while case let accelerator = IOIteratorNext(accelerators), accelerator != 0 {
            defer { IOObjectRelease(accelerator) }
            var clients: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &clients) == KERN_SUCCESS else {
                continue
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

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
