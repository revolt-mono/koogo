import AppKit
import Darwin

/// One running process of the current user and the process macOS holds responsible for it. Cpu and gpu time accumulate since launch, so only their differences between two scans are loads.
struct ProcessRecord: Equatable, Sendable {
    let pid: pid_t
    let responsiblePID: pid_t
    let executablePath: String
    let footprint: UInt64
    let cpuTime: Duration
    let gpuTime: Duration
}

struct ProcessScan: Equatable, Sendable {
    let records: [ProcessRecord]
    let taken: ContinuousClock.Instant
}

/// How a group presents itself: launch services' name and bundle for an app, else what its executable path says.
struct AppIdentity: Equatable, Sendable {
    let name: String
    /// An app bundle or a bare executable; both yield an icon.
    let iconPath: String

    init(executablePath: String) {
        let components = (executablePath as NSString).pathComponents
        iconPath =
            components.lastIndex { $0.hasSuffix(".app") }
            .map { NSString.path(withComponents: Array(components[...$0])) } ?? executablePath
        name = URL(filePath: iconPath).deletingPathExtension().lastPathComponent
    }

    private init(name: String, iconPath: String) {
        self.name = name
        self.iconPath = iconPath
    }

    /// Launch services knows an app by its registered bundle even when it runs from a code-sign clone elsewhere.
    static func running(_ pid: pid_t) -> AppIdentity? {
        guard let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName,
            let bundlePath = app.bundleURL?.path
        else { return nil }
        return AppIdentity(name: name, iconPath: bundlePath)
    }
}

/// The processes one app is responsible for, summed the way activity monitor groups them.
struct AppProcessGroup: Identifiable, Equatable, Sendable {
    /// The responsible process, which stays put while helpers come and go.
    let id: pid_t
    let name: String
    let iconPath: String
    let processCount: Int
    let footprint: UInt64
    /// Cores' worth of cpu time between the two scans; one busy core reads as 1.
    let cpu: Double
    /// Share of the span the gpu spent on the group's work.
    let gpu: Double

    /// The twenty heaviest groups by responsible process. A group whose responsible process is out of sight takes its identity from its oldest member; a process absent from the earlier scan has no load yet.
    static func heaviest(
        in scan: ProcessScan,
        since previous: ProcessScan,
        identity: (pid_t) -> AppIdentity?
    ) -> [AppProcessGroup] {
        let elapsed = scan.taken - previous.taken
        let earlier = Dictionary(previous.records.map { ($0.pid, $0) }) { _, last in last }
        let load = { (record: ProcessRecord, time: KeyPath<ProcessRecord, Duration>) -> Double in
            guard elapsed > .zero, let earlier = earlier[record.pid], record[keyPath: time] >= earlier[keyPath: time]
            else { return 0 }
            return (record[keyPath: time] - earlier[keyPath: time]) / elapsed
        }
        return Dictionary(grouping: scan.records, by: \.responsiblePID)
            .map { responsiblePID, members in
                (id: responsiblePID, members: members, footprint: members.reduce(0) { $0 + $1.footprint })
            }
            .sorted { ($1.footprint, $0.id) < ($0.footprint, $1.id) }
            .prefix(20)
            .map { group in
                let leader = group.members.first { $0.pid == group.id } ?? group.members.min { $0.pid < $1.pid }!
                let identity = identity(leader.pid) ?? AppIdentity(executablePath: leader.executablePath)
                return AppProcessGroup(
                    id: group.id,
                    name: identity.name,
                    iconPath: identity.iconPath,
                    processCount: group.members.count,
                    footprint: group.footprint,
                    cpu: group.members.reduce(0) { $0 + load($1, \.cpuTime) },
                    gpu: group.members.reduce(0) { $0 + load($1, \.gpuTime) }
                )
            }
    }
}

extension ProcessScan {
    private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t
    /// Private in libquarantine; activity monitor uses the same relation.
    private static let responsiblePID = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: ResponsiblePID.self) }
    /// Rusage reports cpu time in mach absolute time units.
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Every process of the current user that still answers; ones exiting mid-scan are skipped.
    static func read() throws -> ProcessScan {
        let pidStride = Int32(MemoryLayout<pid_t>.stride)
        let listedBytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard listedBytes > 0 else { throw ActivityReadFailure.processes }
        // Leave room for processes launched between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(listedBytes / pidStride) + 256)
        let filledBytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), &pids, Int32(pids.count) * pidStride)
        guard filledBytes > 0 else { throw ActivityReadFailure.processes }
        let taken = ContinuousClock.now
        let gpuTimes = GPULoad.timePerProcess()
        return ProcessScan(
            records: pids.prefix(Int(filledBytes / pidStride)).compactMap {
                record($0, gpuTime: gpuTimes[$0] ?? .zero)
            },
            taken: taken
        )
    }

    private static func record(_ pid: pid_t, gpuTime: Duration) -> ProcessRecord? {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        var path = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = Int(proc_pidpath(pid, &path, UInt32(path.count)))
        guard status == 0, pathLength > 0, let executablePath = String(bytes: path.prefix(pathLength), encoding: .utf8)
        else { return nil }
        let responsible = responsiblePID?(pid) ?? pid
        let cpuTicks = usage.ri_user_time + usage.ri_system_time
        return ProcessRecord(
            pid: pid,
            responsiblePID: responsible > 0 ? responsible : pid,
            executablePath: executablePath,
            footprint: usage.ri_phys_footprint,
            cpuTime: .nanoseconds(cpuTicks * UInt64(timebase.numer) / UInt64(timebase.denom)),
            gpuTime: gpuTime
        )
    }
}
