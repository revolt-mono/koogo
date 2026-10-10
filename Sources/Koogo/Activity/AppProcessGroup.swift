import AppKit
import Darwin

/// One running process of the current user and the process macOS holds responsible for it. Cpu and gpu time accumulate since launch, so only their differences between two scans are loads.
struct ProcessRecord: Equatable, Sendable {
    let pid: pid_t
    let responsiblePID: pid_t
    let executablePath: String
    let launched: SuspendingClock.Instant
    let footprint: UInt64
    let cpuTime: Duration
    let gpuTime: Duration
}

/// Timed on the suspending clock, which pauses in sleep like the mach absolute time rusage stamps launches with.
struct ProcessScan: Equatable, Sendable {
    let records: [ProcessRecord]
    let taken: SuspendingClock.Instant
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
    /// Every process in the group, since the responsible one may be out of reach.
    let members: [pid_t]
    let footprint: UInt64
    /// Cores' worth of cpu time between the two scans; one busy core reads as 1.
    let cpu: Double
    /// Share of the span the gpu spent on the group's work.
    let gpu: Double

    var processCount: Int { members.count }

    /// Quits an app the way its menu would, so it can save and close its helpers; any other group gets every member signalled, and one already gone is no failure. The next sample shows what remains.
    func terminate() {
        if NSRunningApplication(processIdentifier: id)?.terminate() == true { return }
        for pid in members where Darwin.kill(pid, SIGTERM) != 0 {
            let error = errno
            if error != ESRCH { Telemetry.activity.error("terminate failed pid=\(pid) errno=\(error)") }
        }
    }

    /// The twenty heaviest groups by responsible process. A group whose responsible process is out of sight takes its identity from its oldest member; a process launched since the earlier scan counts all its time, and one otherwise absent from it has no load yet.
    static func heaviest(
        in scan: ProcessScan,
        since previous: ProcessScan,
        identity: (pid_t) -> AppIdentity?
    ) -> [AppProcessGroup] {
        let elapsed = scan.taken - previous.taken
        let earlier = Dictionary(previous.records.map { ($0.pid, $0) }) { _, last in last }
        let load = { (record: ProcessRecord, time: KeyPath<ProcessRecord, Duration>) -> Double in
            let before = record.launched >= previous.taken ? .zero : earlier[record.pid]?[keyPath: time]
            guard elapsed > .zero, let before, record[keyPath: time] >= before else { return 0 }
            return (record[keyPath: time] - before) / elapsed
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
                    members: group.members.map(\.pid),
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
    /// Rusage reports cpu and launch times in mach absolute time units.
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
    private static let absoluteTimeZero = SuspendingClock.now - duration(ofTicks: mach_absolute_time())

    /// Every process of the current user that still answers; ones exiting mid-scan are skipped.
    static func read() throws -> ProcessScan {
        guard let pids = LibProc.pids(ownedBy: getuid()) else { throw ActivityReadFailure.processes }
        let taken = SuspendingClock.now
        let gpuTimes = GPULoad.timePerProcess()
        return ProcessScan(records: pids.compactMap { record($0, gpuTime: gpuTimes[$0] ?? .zero) }, taken: taken)
    }

    private static func record(_ pid: pid_t, gpuTime: Duration) -> ProcessRecord? {
        guard let usage = LibProc.resourceUsage(of: pid), let executablePath = LibProc.executablePath(of: pid) else {
            return nil
        }
        let responsible = responsiblePID?(pid) ?? pid
        return ProcessRecord(
            pid: pid,
            responsiblePID: responsible > 0 ? responsible : pid,
            executablePath: executablePath,
            launched: absoluteTimeZero + duration(ofTicks: usage.ri_proc_start_abstime),
            footprint: usage.ri_phys_footprint,
            cpuTime: duration(ofTicks: usage.ri_user_time + usage.ri_system_time),
            gpuTime: gpuTime
        )
    }

    private static func duration(ofTicks ticks: UInt64) -> Duration {
        .nanoseconds(ticks * UInt64(timebase.numer) / UInt64(timebase.denom))
    }
}
