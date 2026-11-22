import Darwin
import Foundation
import Synchronization
import Testing

@testable import Koogo

extension EnumMap: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (Key, Value)...) {
    let values = Dictionary(uniqueKeysWithValues: elements)
    precondition(values.count == Key.allCases.count, "a literal must cover every case")
    self.init { values[$0]! }
  }
}

final class Scratch {
  deinit {
    for directory in directories {
      try? FileManager.default.removeItem(at: directory)
    }
    for suiteName in defaultsSuiteNames {
      UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
  }

  func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    directories.append(directory)
    return directory
  }

  func makeIsolatedDefaults() throws -> UserDefaults {
    let suiteName = "KoogoTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaultsSuiteNames.append(suiteName)
    return defaults
  }

  private var directories = [URL]()
  private var defaultsSuiteNames = [String]()
}

enum Poll {
  static func until(
    isolation _: isolated (any Actor)? = #isolation,
    timeout: Duration = .seconds(5),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool,
  ) async throws {
    let deadline = ContinuousClock.now + timeout
    var met = condition()
    while !met, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
      met = condition()
    }
    #expect(met, "condition not met within timeout", sourceLocation: sourceLocation)
  }
}

@Suite(
  .serialized,
  .enabled(
    if: ProcessInfo.processInfo.environment["KOOGO_MEMORY_TESTS"] == "1",
    "Run separately with KOOGO_MEMORY_TESTS=1.",
  ),
)
struct MemoryMeasurement {
  static func allocatedHeapBytes() -> Int {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(malloc_default_zone(), &statistics)
    return statistics.size_in_use
  }
}

enum TestExecutable {
  static func make(in directory: URL, script: String) throws -> URL {
    let executable = directory.appending(path: UUID().uuidString)
    try script.write(to: executable.appendingPathExtension("sh"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: launcher)
    return executable
  }

  /// macos vets each new executable file at its first launch, one file at a time, so scripts launched together
  /// queue past the deadlines tests assert. every script is sourced through a link to this one launcher instead.
  private static let launcher = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "launcher")
}

final class Counter: Sendable {
  var value: Int {
    count.withLock { $0 }
  }

  @discardableResult
  func increment() -> Int {
    count.withLock {
      $0 += 1
      return $0
    }
  }

  private let count = Mutex(0)
}
