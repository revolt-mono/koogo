import Foundation
import XCTest

extension XCTestCase {
    /// A fresh directory, removed when the test ends.
    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    /// Defaults backed by a fresh suite, so tests never read or write the runner's own defaults;
    /// the suite is removed when the test ends.
    func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "KoogoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

/// Polls `condition` every 10 ms on the caller's actor until it holds or `timeout` passes,
/// then asserts it.
func waitUntil(
    isolation: isolated (any Actor)? = #isolation,
    timeout: Duration = .seconds(5),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition(), "condition not met within timeout", file: file, line: line)
}
