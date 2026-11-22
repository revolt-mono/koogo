import Foundation
import Testing

@testable import Koogo

struct ProcessScanTests {
  @Test
  func `the running machine measures this process`() async {
    await #expect(processExitsWith: .success) {
      let before = try ProcessScan.read(after: nil)
      let spinUntil = ContinuousClock.now + .milliseconds(300)
      while ContinuousClock.now < spinUntil { }
      let after = try ProcessScan.read(after: before)

      let earlier = try #require(before.records.first { $0.pid == getpid() })
      let later = try #require(after.records.first { $0.pid == getpid() })
      #expect(later.footprint > 0)
      #expect(later.responsiblePID > 0)
      #expect(later.parentPID == getppid())
      #expect(later.executablePath.hasPrefix("/"))
      let busy = later.cpuTime - earlier.cpuTime
      #expect(busy >= .milliseconds(250))
      #expect(busy < after.taken - before.taken + .milliseconds(100))
      #expect(after.records.contains { $0.gpuTime > .zero })
    }
  }

  @Test
  func `the running machine stamps a process with its launch`() async throws {
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

    let launched = try #require(scanned)
    #expect(launched >= beforeLaunch)
    #expect(launched <= afterLaunch)
  }

  @Test
  func `a rescan follows a process that execs another image`() async throws {
    let child = Process()
    child.executableURL = URL(filePath: "/bin/zsh")
    child.arguments = ["-c", "read line; exec /bin/sleep 10"]
    let input = Pipe()
    child.standardInput = input
    try child.run()
    defer { child.terminate() }
    let beforeExec = try ProcessScan.read(after: nil)
    let shell = try #require(beforeExec.records.first { $0.pid == child.processIdentifier })
    #expect(shell.executablePath == "/bin/zsh")

    try input.fileHandleForWriting.write(contentsOf: Data("go\n".utf8))
    var execed: ProcessRecord?
    try await Poll.until {
      execed = try? ProcessScan.read(after: beforeExec).records.first {
        $0.pid == child.processIdentifier && $0.pidVersion != shell.pidVersion
      }
      return execed != nil
    }

    #expect(execed?.identity == shell.identity)
    #expect(execed?.executablePath == "/bin/sleep")
  }

  @Test
  func `a rescan hands a process back to itself once its responsible process exits`() async throws {
    let shell = try spawnResponsibleForItself("/bin/zsh", "-c", "/bin/sleep 10 & wait")
    defer {
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
    let orphan = try #require(sleeper)
    let before = try #require(scan)
    defer { kill(orphan.pid, SIGKILL) }
    #expect(orphan.responsiblePID == shell)

    kill(shell, SIGKILL)

    // the shell stays an unreaped zombie, which the kernel no longer counts as responsible.
    try await Poll.until {
      (try? ProcessScan.read(after: before))?.records.first { $0.pid == orphan.pid }?.responsiblePID == orphan.pid
    }
  }

  /// disclaims responsibility the way launch services does for apps.
  private func spawnResponsibleForItself(_ arguments: String...) throws -> pid_t {
    typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    let disclaim = try #require(dlsym(dlopen(nil, RTLD_NOW), "responsibility_spawnattrs_setdisclaim"))
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    #expect(unsafeBitCast(disclaim, to: Disclaim.self)(&attributes, 1) == 0)
    let argv = arguments.map { strdup($0) } + [nil]
    defer { for item in argv { free(item) } }
    var pid: pid_t = 0
    #expect(posix_spawn(&pid, arguments[0], nil, &attributes, argv, environ) == 0)
    return pid
  }
}
