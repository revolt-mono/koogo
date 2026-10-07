import XCTest

@testable import Koogo

final class AppProcessGroupTests: XCTestCase {
    private let start = ContinuousClock.now

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
        XCTAssertEqual(groups.map(\.processCount), [1, 3, 1])
        XCTAssertEqual(groups.map(\.footprint), [100, 90, 5])
        XCTAssertEqual(groups.map(\.cpu), [0, 0.5, 0])
        XCTAssertEqual(groups.map(\.gpu), [0.2, 0, 0])
        XCTAssertEqual(
            groups.map(\.iconPath),
            ["/Applications/Slack.app", "/Applications/Chromium.app", "/bin/zsh"]
        )
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
        XCTAssertEqual(groups.map(\.processCount), [2])
    }

    func testAReusedPIDWithLessCPUTimeThanBeforeHasNoLoad() {
        let earlier = ProcessScan(
            records: [record(pid: 7, responsiblePID: 7, path: "/bin/zsh", footprint: 1, cpuTime: .seconds(9))],
            taken: start
        )
        let now = ProcessScan(
            records: [record(pid: 7, responsiblePID: 7, path: "/bin/zsh", footprint: 1, cpuTime: .seconds(1))],
            taken: start + .seconds(10)
        )

        XCTAssertEqual(AppProcessGroup.heaviest(in: now, since: earlier) { _ in nil }.map(\.cpu), [0])
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
        XCTAssertTrue(later.executablePath.hasPrefix("/"), later.executablePath)
        let busy = later.cpuTime - earlier.cpuTime
        XCTAssertGreaterThanOrEqual(busy, .milliseconds(250), "\(busy)")
        XCTAssertLessThan(busy, after.taken - before.taken + .milliseconds(100), "\(busy)")

        let groups = AppProcessGroup.heaviest(in: after, since: before, identity: AppIdentity.running)

        XCTAssertFalse(groups.isEmpty)
        XCTAssertLessThanOrEqual(groups.count, 20)
        XCTAssertEqual(groups.map(\.footprint), groups.map(\.footprint).sorted(by: >))
        XCTAssertTrue(groups.allSatisfy { (0...1).contains($0.gpu) }, "\(groups.map(\.gpu))")
        XCTAssertTrue(after.records.contains { $0.gpuTime > .zero })
    }

    private func record(
        pid: pid_t,
        responsiblePID: pid_t,
        path: String,
        footprint: UInt64,
        cpuTime: Duration = .zero,
        gpuTime: Duration = .zero
    ) -> ProcessRecord {
        ProcessRecord(
            pid: pid,
            responsiblePID: responsiblePID,
            executablePath: path,
            footprint: footprint,
            cpuTime: cpuTime,
            gpuTime: gpuTime
        )
    }
}
