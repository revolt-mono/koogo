import XCTest

@testable import Koogo

final class AppProcessGroupTests: XCTestCase {
    private let start = SuspendingClock.now

    func testGroupsByResponsibleProcessHeaviestFirstUnderItsAppsIdentity() {
        let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"
        let slack = "/Applications/Slack.app/Contents/MacOS/Slack"
        let earlier = ProcessScan(
            records: [
                record(pid: 300, responsiblePID: 300, path: "/bin/zsh", footprint: 5, cpuTime: .seconds(1)),
                record(pid: 100, responsiblePID: 100, path: chrome, footprint: 40, cpuTime: .seconds(10)),
                record(pid: 101, responsiblePID: 100, path: helper, footprint: 30, cpuTime: .seconds(2)),
                record(pid: 200, responsiblePID: 200, path: slack, footprint: 100, gpuTime: .seconds(1)),
            ],
            taken: start
        )
        let now = ProcessScan(
            records: [
                record(pid: 300, responsiblePID: 300, path: "/bin/zsh", footprint: 5, cpuTime: .seconds(1)),
                record(pid: 100, responsiblePID: 100, path: chrome, footprint: 40, cpuTime: .seconds(12)),
                record(pid: 101, responsiblePID: 100, path: helper, footprint: 30, cpuTime: .seconds(5)),
                record(pid: 102, responsiblePID: 100, path: helper, footprint: 20, cpuTime: .seconds(9)),
                record(pid: 200, responsiblePID: 200, path: slack, footprint: 100, gpuTime: .seconds(3)),
            ],
            taken: start + .seconds(10)
        )

        let groups = AppProcessGroup.heaviest(in: now, since: earlier) { pid in
            pid == 100 ? AppIdentity(executablePath: "/Applications/Chromium.app/Contents/MacOS/Chromium") : nil
        }

        XCTAssertEqual(groups.map(\.id), [200, 100, 300])
        XCTAssertEqual(groups.map(\.name), ["Slack", "Chromium", "zsh"])
        XCTAssertEqual(groups.map { $0.members.map(\.pid) }, [[200], [100, 101, 102], [300]])
        XCTAssertEqual(
            groups.map { $0.members.map(\.name) },
            [["Slack"], ["Google Chrome", "Helper", "Helper"], ["zsh"]]
        )
        XCTAssertEqual(groups.map { $0.members.map(\.depth) }, [[0], [0, 1, 1], [0]])
        XCTAssertEqual(groups.map { $0.members.map(\.cpu) }, [[0], [0.2, 0.3, 0], [0]])
        XCTAssertEqual(groups.map { $0.members.map(\.gpu) }, [[0.2], [0, 0, 0], [0]])
        XCTAssertEqual(groups.map(\.footprint), [100, 90, 5])
        XCTAssertEqual(groups.map(\.cpu), [0, 0.5, 0])
        XCTAssertEqual(groups.map(\.gpu), [0.2, 0, 0])
        XCTAssertEqual(
            groups.map(\.iconPath),
            ["/Applications/Slack.app", "/Applications/Chromium.app", "/bin/zsh"]
        )
    }

    func testMembersNestUnderTheirParentsHeaviestFirstAtEveryLevel() throws {
        let scan = ProcessScan(
            records: [
                record(pid: 104, parentPID: 7, responsiblePID: 100, path: "/usr/bin/git", footprint: 1),
                record(pid: 103, parentPID: 102, responsiblePID: 100, path: "/usr/bin/ssh", footprint: 5),
                record(pid: 101, parentPID: 100, responsiblePID: 100, path: "/bin/zsh", footprint: 30),
                record(pid: 102, parentPID: 100, responsiblePID: 100, path: "/bin/bash", footprint: 50),
                record(
                    pid: 100,
                    parentPID: 1,
                    responsiblePID: 100,
                    path: "/Applications/Ghostty.app/Contents/MacOS/ghostty",
                    footprint: 10
                ),
            ],
            taken: start
        )

        let members = try XCTUnwrap(AppProcessGroup.heaviest(in: scan, since: scan) { _ in nil }.first).members

        XCTAssertEqual(members.map(\.pid), [100, 102, 103, 101, 104])
        XCTAssertEqual(members.map(\.depth), [0, 1, 2, 1, 0])
        XCTAssertEqual(members.map(\.name), ["ghostty", "bash", "ssh", "zsh", "git"])
    }

    func testOldestMemberNamesAGroupWhoseResponsibleProcessIsUnseen() {
        let scan = ProcessScan(
            records: [
                record(pid: 52, responsiblePID: 9, path: "/usr/bin/python3", footprint: 1),
                record(pid: 51, responsiblePID: 9, path: "/usr/local/bin/node", footprint: 1),
            ],
            taken: start
        )

        let groups = AppProcessGroup.heaviest(in: scan, since: scan) { _ in nil }

        XCTAssertEqual(groups.map(\.name), ["node"])
        XCTAssertEqual(groups.map(\.iconPath), ["/usr/local/bin/node"])
        XCTAssertEqual(groups.map(\.members.count), [2])
    }

    func testGPUTimeThatFellWithAClosedClientHasNoLoad() {
        let earlier = ProcessScan(
            records: [record(pid: 7, responsiblePID: 7, path: "/bin/zsh", footprint: 1, gpuTime: .seconds(9))],
            taken: start
        )
        let now = ProcessScan(
            records: [record(pid: 7, responsiblePID: 7, path: "/bin/zsh", footprint: 1, gpuTime: .seconds(1))],
            taken: start + .seconds(10)
        )

        XCTAssertEqual(AppProcessGroup.heaviest(in: now, since: earlier) { _ in nil }.map(\.gpu), [0])
    }

    func testAProcessLaunchedSinceTheEarlierScanCountsAllItsTime() {
        let earlier = ProcessScan(
            records: [record(pid: 7, responsiblePID: 7, path: "/bin/zsh", footprint: 2, cpuTime: .seconds(9))],
            taken: start
        )
        let launched = start + .seconds(1)
        let now = ProcessScan(
            records: [
                record(
                    pid: 7,
                    responsiblePID: 7,
                    path: "/bin/zsh",
                    footprint: 2,
                    launched: launched,
                    cpuTime: .seconds(10)
                ),
                record(
                    pid: 8,
                    responsiblePID: 8,
                    path: "/usr/bin/git",
                    footprint: 1,
                    launched: launched,
                    cpuTime: .seconds(2),
                    gpuTime: .seconds(1)
                ),
            ],
            taken: start + .seconds(10)
        )

        let groups = AppProcessGroup.heaviest(in: now, since: earlier) { _ in nil }

        XCTAssertEqual(groups.map(\.cpu), [1, 0.2])
        XCTAssertEqual(groups.map(\.gpu), [0, 0.1])
    }

    func testTheRunningMachineMeasuresThisProcessAndRanksTheHeaviestGroups() throws {
        let before = try ProcessScan.read()
        let spinUntil = ContinuousClock.now + .milliseconds(300)
        var spins = 0
        while ContinuousClock.now < spinUntil {
            spins += 1
        }
        XCTAssertGreaterThan(spins, 0)
        let after = try ProcessScan.read()

        let earlier = try XCTUnwrap(before.records.first { $0.pid == getpid() })
        let later = try XCTUnwrap(after.records.first { $0.pid == getpid() })
        XCTAssertGreaterThan(later.footprint, 0)
        XCTAssertGreaterThan(later.responsiblePID, 0)
        XCTAssertEqual(later.parentPID, getppid())
        XCTAssertTrue(later.executablePath.hasPrefix("/"), later.executablePath)
        let busy = later.cpuTime - earlier.cpuTime
        XCTAssertGreaterThanOrEqual(busy, .milliseconds(250), "\(busy)")
        XCTAssertLessThan(busy, after.taken - before.taken + .milliseconds(100), "\(busy)")

        let groups = AppProcessGroup.heaviest(in: after, since: before, identity: AppIdentity.running)

        XCTAssertFalse(groups.isEmpty)
        XCTAssertLessThanOrEqual(groups.count, 20)
        XCTAssertEqual(groups.map(\.footprint), groups.map(\.footprint).sorted(by: >))
        XCTAssertTrue(groups.allSatisfy { $0.cpu >= 0 && $0.gpu >= 0 }, "\(groups.map { ($0.cpu, $0.gpu) })")
        XCTAssertTrue(after.records.contains { $0.gpuTime > .zero })
    }

    func testTheRunningMachineStampsAProcessWithItsLaunch() async throws {
        let child = Process()
        child.executableURL = URL(filePath: "/bin/sleep")
        child.arguments = ["10"]
        let beforeLaunch = SuspendingClock.now
        try child.run()
        let afterLaunch = SuspendingClock.now
        defer { child.terminate() }

        var scanned: SuspendingClock.Instant?
        try await waitUntil {
            scanned = (try? ProcessScan.read())?.records.first { $0.pid == child.processIdentifier }?.launched
            return scanned != nil
        }

        let launched = try XCTUnwrap(scanned)
        XCTAssertGreaterThanOrEqual(launched, beforeLaunch)
        XCTAssertLessThanOrEqual(launched, afterLaunch)
    }

    func testForceTerminatingAGroupKillsEveryMemberAndSurvivesOneAlreadyGone() async throws {
        let child = Process()
        child.executableURL = URL(filePath: "/bin/sleep")
        child.arguments = ["10"]
        try child.run()
        addTeardownBlock { child.terminate() }
        let identity = try XCTUnwrap(LibProc.identity(of: child.processIdentifier))
        let scan = ProcessScan(
            records: [
                record(pid: 2_147_483_000, responsiblePID: 1, path: "/bin/sleep", footprint: 1),
                record(identity: identity, responsiblePID: 1, path: "/bin/sleep", footprint: 1),
            ],
            taken: start
        )
        let group = try XCTUnwrap(AppProcessGroup.heaviest(in: scan, since: scan) { _ in nil }.first)

        group.forceTerminate()

        try await waitUntil { !child.isRunning }
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
    }

    func testForceTerminatingSparesAProcessThatTookOverAScannedPID() async throws {
        let child = Process()
        child.executableURL = URL(filePath: "/bin/sleep")
        child.arguments = ["10"]
        try child.run()
        addTeardownBlock { child.terminate() }
        let identity = try XCTUnwrap(LibProc.identity(of: child.processIdentifier))
        let earlierOwner = ProcessIdentity(pid: identity.pid, startTicks: identity.startTicks - 1)
        let scan = ProcessScan(
            records: [record(identity: earlierOwner, responsiblePID: 1, path: "/bin/sleep", footprint: 1)],
            taken: start
        )
        let group = try XCTUnwrap(AppProcessGroup.heaviest(in: scan, since: scan) { _ in nil }.first)

        group.forceTerminate()

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(child.isRunning)
    }

    /// a group leader descends from launchd; other members default to children of their responsible process.
    private func record(
        pid: pid_t,
        parentPID: pid_t? = nil,
        responsiblePID: pid_t,
        path: String,
        footprint: UInt64,
        launched: SuspendingClock.Instant? = nil,
        cpuTime: Duration = .zero,
        gpuTime: Duration = .zero
    ) -> ProcessRecord {
        record(
            identity: ProcessIdentity(pid: pid, startTicks: 0),
            parentPID: parentPID ?? (responsiblePID == pid ? 1 : responsiblePID),
            responsiblePID: responsiblePID,
            path: path,
            footprint: footprint,
            launched: launched,
            cpuTime: cpuTime,
            gpuTime: gpuTime
        )
    }

    private func record(
        identity: ProcessIdentity,
        parentPID: pid_t = 1,
        responsiblePID: pid_t,
        path: String,
        footprint: UInt64,
        launched: SuspendingClock.Instant? = nil,
        cpuTime: Duration = .zero,
        gpuTime: Duration = .zero
    ) -> ProcessRecord {
        ProcessRecord(
            identity: identity,
            parentPID: parentPID,
            responsiblePID: responsiblePID,
            executablePath: path,
            launched: launched ?? start - .seconds(60),
            footprint: footprint,
            cpuTime: cpuTime,
            gpuTime: gpuTime
        )
    }
}
