import AppKit
import Darwin
import os

/// cpu and gpu times accumulate since launch; scan differences yield load for each user process.
struct ProcessRecord: Sendable {
    let identity: ProcessIdentity
    let parentPID: pid_t
    let responsiblePID: pid_t
    let executablePath: String
    let launched: SuspendingClock.Instant
    let footprint: UInt64
    let cpuTime: Duration
    let gpuTime: Duration

    var pid: pid_t { identity.pid }
}

/// the suspending clock pauses during sleep, matching mach absolute launch timestamps.
struct ProcessScan: Sendable {
    let records: [ProcessRecord]
    let taken: SuspendingClock.Instant
}

struct AppIdentity: Sendable {
    let name: String
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

    /// launch services resolves registered bundles even when executables run from code-sign clones.
    static func running(_ pid: pid_t) -> AppIdentity? {
        guard let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName,
            let bundlePath = app.bundleURL?.path
        else { return nil }
        return AppIdentity(name: name, iconPath: bundlePath)
    }
}

struct AppProcessMember: Sendable {
    let identity: ProcessIdentity
    let name: String
    /// a member whose parent runs outside the group sits at 0.
    let depth: Int
    let footprint: UInt64
    let cpu: Double
    let gpu: Double

    var pid: pid_t { identity.pid }
}

struct AppProcessGroup: Identifiable, Sendable {
    let id: pid_t
    let name: String
    let iconPath: String
    /// preorder under each parent, heaviest siblings first.
    let members: [AppProcessMember]
    let footprint: UInt64
    /// cpu cores used between scans; one busy core reads as 1.
    let cpu: Double
    /// fraction of the sample span spent on the group's gpu work.
    let gpu: Double

    func forceTerminate() {
        for member in members {
            do {
                try LibProc.forceKill(member.identity)
            } catch {
                Logger.activity.error("force terminate failed pid=\(member.pid): \(error, privacy: .public)")
            }
        }
    }

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
                let members = nested(group.members, load: load)
                return AppProcessGroup(
                    id: group.id,
                    name: identity.name,
                    iconPath: identity.iconPath,
                    members: members,
                    footprint: group.footprint,
                    cpu: members.reduce(0) { $0 + $1.cpu },
                    gpu: members.reduce(0) { $0 + $1.gpu }
                )
            }
    }

    private static func nested(
        _ records: [ProcessRecord],
        load: (ProcessRecord, KeyPath<ProcessRecord, Duration>) -> Double
    ) -> [AppProcessMember] {
        let children = Dictionary(grouping: records, by: \.parentPID)
        let pids = Set(records.map(\.pid))
        func nest(_ siblings: [ProcessRecord], depth: Int) -> [AppProcessMember] {
            siblings.sorted { ($1.footprint, $0.pid) < ($0.footprint, $1.pid) }
                .flatMap { record in
                    let member = AppProcessMember(
                        identity: record.identity,
                        name: URL(filePath: record.executablePath).lastPathComponent,
                        depth: depth,
                        footprint: record.footprint,
                        cpu: load(record, \.cpuTime),
                        gpu: load(record, \.gpuTime)
                    )
                    return [member] + nest(children[record.pid] ?? [], depth: depth + 1)
                }
        }
        return nest(records.filter { !pids.contains($0.parentPID) }, depth: 0)
    }
}

extension ProcessScan {
    private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t
    /// private libquarantine relation also used by activity monitor.
    private static let responsiblePID = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: ResponsiblePID.self) }
    /// resource usage reports cpu and launch times in mach absolute units.
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
    private static let absoluteTimeZero = SuspendingClock.now - duration(ofTicks: mach_absolute_time())

    static func read() throws -> ProcessScan {
        guard let pids = LibProc.currentUserPIDs() else { throw ActivityReadFailure.processes }
        let taken = SuspendingClock.now
        let gpuTimes = GPULoad.timePerProcess()
        return ProcessScan(records: pids.compactMap { record($0, gpuTime: gpuTimes[$0] ?? .zero) }, taken: taken)
    }

    private static func record(_ pid: pid_t, gpuTime: Duration) -> ProcessRecord? {
        guard
            let usage = LibProc.resourceUsage(of: pid),
            let info = LibProc.bsdInfo(of: pid),
            let executablePath = LibProc.executablePath(of: pid)
        else { return nil }
        let responsible = responsiblePID?(pid) ?? pid
        return ProcessRecord(
            identity: ProcessIdentity(pid: pid, startTicks: usage.ri_proc_start_abstime),
            parentPID: pid_t(info.pbi_ppid),
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
