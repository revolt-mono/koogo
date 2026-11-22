import XCTest

@testable import Koogo

final class ProcessScanTests: XCTestCase {
  func testTheRunningMachineMeasuresThisProcess() throws {
    let before = try ProcessScan.read(after: nil)
    let spinUntil = ContinuousClock.now + .milliseconds(300)
    while ContinuousClock.now < spinUntil { }
    let after = try ProcessScan.read(after: before)

    let earlier = try XCTUnwrap(before.records.first { $0.pid == getpid() })
    let later = try XCTUnwrap(after.records.first { $0.pid == getpid() })
    XCTAssertGreaterThan(later.footprint, 0)
    XCTAssertGreaterThan(later.responsiblePID, 0)
    XCTAssertEqual(later.parentPID, getppid())
    XCTAssertTrue(later.executablePath.hasPrefix("/"), later.executablePath)
    let busy = later.cpuTime - earlier.cpuTime
    XCTAssertGreaterThanOrEqual(busy, .milliseconds(250), "\(busy)")
    XCTAssertLessThan(busy, after.taken - before.taken + .milliseconds(100), "\(busy)")
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
    try await Poll.until {
      scanned = (try? ProcessScan.read(after: nil))?.records.first { $0.pid == child.processIdentifier }?.launched
      return scanned != nil
    }

    let launched = try XCTUnwrap(scanned)
    XCTAssertGreaterThanOrEqual(launched, beforeLaunch)
    XCTAssertLessThanOrEqual(launched, afterLaunch)
  }

  func testARescanFollowsAProcessThatExecsAnotherImage() async throws {
    let child = Process()
    child.executableURL = URL(filePath: "/bin/zsh")
    child.arguments = ["-c", "read line; exec /bin/sleep 10"]
    let input = Pipe()
    child.standardInput = input
    try child.run()
    addTeardownBlock { child.terminate() }
    let beforeExec = try ProcessScan.read(after: nil)
    let shell = try XCTUnwrap(beforeExec.records.first { $0.pid == child.processIdentifier })
    XCTAssertEqual(shell.executablePath, "/bin/zsh")

    try input.fileHandleForWriting.write(contentsOf: Data("go\n".utf8))
    var execed: ProcessRecord?
    try await Poll.until {
      execed = try? ProcessScan.read(after: beforeExec).records.first {
        $0.pid == child.processIdentifier && $0.pidVersion != shell.pidVersion
      }
      return execed != nil
    }

    XCTAssertEqual(execed?.identity, shell.identity)
    XCTAssertEqual(execed?.executablePath, "/bin/sleep")
  }

  func testARescanHandsAProcessBackToItselfOnceItsResponsibleProcessExits() async throws {
    let shell = try spawnResponsibleForItself("/bin/zsh", "-c", "/bin/sleep 10 & wait")
    addTeardownBlock {
      kill(shell, SIGKILL)
      waitpid(shell, nil, 0)
    }
    var scan: ProcessScan?
    var sleeper: ProcessRecord?
    try await Poll.until {
      scan = try? ProcessScan.read(after: nil)
      sleeper = scan?.records.first { $0.parentPID == shell }
      return sleeper != nil
    }
    let orphan = try XCTUnwrap(sleeper)
    let before = try XCTUnwrap(scan)
    addTeardownBlock { kill(orphan.pid, SIGKILL) }
    XCTAssertEqual(orphan.responsiblePID, shell)

    kill(shell, SIGKILL)

    // the shell stays an unreaped zombie, which the kernel no longer counts as responsible.
    try await Poll.until {
      (try? ProcessScan.read(after: before))?.records.first { $0.pid == orphan.pid }?.responsiblePID == orphan.pid
    }
  }

  /// disclaims responsibility the way launch services does for apps.
  private func spawnResponsibleForItself(_ arguments: String...) throws -> pid_t {
    typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    let disclaim = try XCTUnwrap(dlsym(dlopen(nil, RTLD_NOW), "responsibility_spawnattrs_setdisclaim"))
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    XCTAssertEqual(unsafeBitCast(disclaim, to: Disclaim.self)(&attributes, 1), 0)
    let argv = arguments.map { strdup($0) } + [nil]
    defer { for item in argv { free(item) } }
    var pid: pid_t = 0
    XCTAssertEqual(posix_spawn(&pid, arguments[0], nil, &attributes, argv, environ), 0)
    return pid
  }
}
