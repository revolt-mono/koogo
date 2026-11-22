import Foundation
import Testing

@testable import Koogo

struct AppProcessGroupTests {
  @Test
  func `groups by responsible process heaviest first under its apps identity`() {
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
      taken: start,
    )
    let now = ProcessScan(
      records: [
        record(pid: 300, responsiblePID: 300, path: "/bin/zsh", footprint: 5, cpuTime: .seconds(1)),
        record(pid: 100, responsiblePID: 100, path: chrome, footprint: 40, cpuTime: .seconds(12)),
        record(pid: 101, responsiblePID: 100, path: helper, footprint: 30, cpuTime: .seconds(5)),
        record(pid: 102, responsiblePID: 100, path: helper, footprint: 20, cpuTime: .seconds(9)),
        record(pid: 200, responsiblePID: 200, path: slack, footprint: 100, gpuTime: .seconds(3)),
      ],
      taken: start + .seconds(10),
    )

    let groups = AppProcessGroup.heaviest(in: now, since: earlier) {
      $0.pid == 100 ? AppIdentity(executablePath: "/Applications/Chromium.app/Contents/MacOS/Chromium") : nil
    }

    #expect(groups.map(\.id) == [200, 100, 300])
    #expect(groups.map(\.name) == ["Slack", "Chromium", "zsh"])
    #expect(groups.map { $0.members.map(\.pid) } == [[200], [100, 101, 102], [300]])
    #expect(groups.map { $0.members.map(\.name) } == [["Slack"], ["Google Chrome", "Helper", "Helper"], ["zsh"]])
    #expect(groups.map { $0.members.map(\.depth) } == [[0], [0, 1, 1], [0]])
    #expect(groups.map { $0.members.map(\.cpu) } == [[0], [0.2, 0.3, 0], [0]])
    #expect(groups.map { $0.members.map(\.gpu) } == [[0.2], [0, 0, 0], [0]])
    #expect(groups.map(\.footprint) == [100, 90, 5])
    #expect(groups.map(\.cpu) == [0, 0.5, 0])
    #expect(groups.map(\.gpu) == [0.2, 0, 0])
    #expect(groups.map(\.iconPath) == ["/Applications/Slack.app", "/Applications/Chromium.app", "/bin/zsh"])
  }

  @Test
  func `members nest under their parents heaviest first at every level`() throws {
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
          footprint: 10,
        ),
      ],
      taken: start,
    )

    let members = try #require(AppProcessGroup.heaviest(in: scan, since: scan) { _ in nil }.first).members

    #expect(members.map(\.pid) == [100, 102, 103, 101, 104])
    #expect(members.map(\.depth) == [0, 1, 2, 1, 0])
    #expect(members.map(\.name) == ["ghostty", "bash", "ssh", "zsh", "git"])
  }

  @Test
  func `oldest member names a group whose responsible process is unseen`() {
    let scan = ProcessScan(
      records: [
        record(pid: 51, responsiblePID: 9, path: "/usr/bin/python3", footprint: 1),
        record(
          pid: 52,
          responsiblePID: 9,
          path: "/usr/local/bin/node",
          footprint: 1,
          launched: start - .seconds(90),
        ),
      ],
      taken: start,
    )

    let groups = AppProcessGroup.heaviest(in: scan, since: scan) { _ in nil }

    #expect(groups.map(\.name) == ["node"])
    #expect(groups.map(\.iconPath) == ["/usr/local/bin/node"])
    #expect(groups.map(\.members.count) == [2])
  }

  @Test
  func `gpu time that fell with a closed client has no load`() {
    let earlier = ProcessScan(
      records: [record(pid: 7, responsiblePID: 7, path: "/bin/zsh", footprint: 1, gpuTime: .seconds(9))],
      taken: start,
    )
    let now = ProcessScan(
      records: [record(pid: 7, responsiblePID: 7, path: "/bin/zsh", footprint: 1, gpuTime: .seconds(1))],
      taken: start + .seconds(10),
    )

    #expect(AppProcessGroup.heaviest(in: now, since: earlier) { _ in nil }.map(\.gpu) == [0])
  }

  @Test
  func `a process launched since the earlier scan counts all its time`() {
    let earlier = ProcessScan(
      records: [record(pid: 7, responsiblePID: 7, path: "/bin/zsh", footprint: 2, cpuTime: .seconds(9))],
      taken: start,
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
          cpuTime: .seconds(10),
        ),
        record(
          pid: 8,
          responsiblePID: 8,
          path: "/usr/bin/git",
          footprint: 1,
          launched: launched,
          cpuTime: .seconds(2),
          gpuTime: .seconds(1),
        ),
      ],
      taken: start + .seconds(10),
    )

    let groups = AppProcessGroup.heaviest(in: now, since: earlier) { _ in nil }

    #expect(groups.map(\.cpu) == [1, 0.2])
    #expect(groups.map(\.gpu) == [0, 0.1])
  }

  @Test
  func `the running machine ranks the heaviest groups`() throws {
    let before = try ProcessScan.read(after: nil)
    let after = try ProcessScan.read(after: before)

    let groups = AppProcessGroup.heaviest(in: after, since: before) { AppIdentity.running($0.pid) }

    #expect(!groups.isEmpty)
    #expect(groups.count <= 20)
    #expect(groups.map(\.footprint) == groups.map(\.footprint).sorted(by: >))
    #expect(groups.allSatisfy { $0.cpu >= 0 && $0.gpu >= 0 }, "\(groups.map { ($0.cpu, $0.gpu) })")
  }

  @Test
  func `force terminating a group kills every member and survives one already gone`() async throws {
    let child = Process()
    child.executableURL = URL(filePath: "/bin/sleep")
    child.arguments = ["10"]
    try child.run()
    defer { child.terminate() }
    let identity = try #require(LibProc.identity(of: child.processIdentifier))
    let scan = ProcessScan(
      records: [
        record(pid: 2_147_483_000, responsiblePID: 1, path: "/bin/sleep", footprint: 1),
        record(identity: identity, responsiblePID: 1, path: "/bin/sleep", footprint: 1),
      ],
      taken: start,
    )
    let group = try #require(AppProcessGroup.heaviest(in: scan, since: scan) { _ in nil }.first)

    group.forceTerminate()

    try await Poll.until { !child.isRunning }
    #expect(child.terminationReason == .uncaughtSignal)
  }

  @Test
  func `force terminating spares a process that took over a scanned pid`() async throws {
    let child = Process()
    child.executableURL = URL(filePath: "/bin/sleep")
    child.arguments = ["10"]
    try child.run()
    defer { child.terminate() }
    let identity = try #require(LibProc.identity(of: child.processIdentifier))
    let earlierOwner = ProcessIdentity(pid: identity.pid, startTicks: identity.startTicks - 1)
    let scan = ProcessScan(
      records: [record(identity: earlierOwner, responsiblePID: 1, path: "/bin/sleep", footprint: 1)],
      taken: start,
    )
    let group = try #require(AppProcessGroup.heaviest(in: scan, since: scan) { _ in nil }.first)

    group.forceTerminate()

    try await Task.sleep(for: .milliseconds(200))
    #expect(child.isRunning)
  }

  private static let launchdPID: pid_t = 1

  private let start = SuspendingClock.now

  private func record(
    pid: pid_t,
    parentPID: pid_t? = nil,
    responsiblePID: pid_t,
    path: String,
    footprint: UInt64,
    launched: SuspendingClock.Instant? = nil,
    cpuTime: Duration = .zero,
    gpuTime: Duration = .zero,
  ) -> ProcessRecord {
    record(
      identity: ProcessIdentity(pid: pid, startTicks: 0),
      parentPID: parentPID ?? (responsiblePID == pid ? Self.launchdPID : responsiblePID),
      responsiblePID: responsiblePID,
      path: path,
      footprint: footprint,
      launched: launched,
      cpuTime: cpuTime,
      gpuTime: gpuTime,
    )
  }

  private func record(
    identity: ProcessIdentity,
    parentPID: pid_t = launchdPID,
    responsiblePID: pid_t,
    path: String,
    footprint: UInt64,
    launched: SuspendingClock.Instant? = nil,
    cpuTime: Duration = .zero,
    gpuTime: Duration = .zero,
  ) -> ProcessRecord {
    ProcessRecord(
      identity: identity,
      pidVersion: identity.pid,
      parentPID: parentPID,
      responsiblePID: responsiblePID,
      executablePath: path,
      launched: launched ?? start - .seconds(60),
      footprint: footprint,
      cpuTime: cpuTime,
      gpuTime: gpuTime,
    )
  }
}
