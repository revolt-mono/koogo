import Darwin
import Foundation
import Synchronization
import XCTest

@testable import Koogo

extension EnumMap: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Key, Value)...) {
        let values = Dictionary(uniqueKeysWithValues: elements)
        precondition(values.count == Key.allCases.count, "a literal must cover every case")
        self.init { values[$0]! }
    }
}

extension XCTestCase {
    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "KoogoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func compileKoogoClient(_ source: String) async throws -> (status: Int32, diagnostics: String) {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appending(path: "Contract.swift")
        let diagnosticsURL = directory.appending(path: "diagnostics")
        try "@testable import Koogo\n\(source)".write(to: sourceURL, atomically: true, encoding: .utf8)
        let executable = try makeTestExecutable(
            in: directory,
            script: """
                #!/bin/sh
                export DEVELOPER_DIR="$1"
                diagnostics="$2"
                shift 2
                /usr/bin/xcrun swiftc "$@" > "$diagnostics" 2>&1
                printf '%s\\n' "$?"
                """
        )

        let products = Bundle(for: type(of: self)).bundleURL.deletingLastPathComponent()
        let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let shims = repository.appending(path: ".build/checkouts/swift-subprocess/Sources/_SubprocessCShims/include")
        #if arch(arm64)
        let target = "arm64-apple-macos26.0"
        #else
        let target = "x86_64-apple-macos26.0"
        #endif
        let developer =
            ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
            ?? "/Applications/Xcode-beta.app/Contents/Developer"
        let arguments = [
            developer, diagnosticsURL.path, "-c", "-swift-version", "6", "-target", target,
            "-I", products.path, "-F", products.path, "-F", products.appending(path: "PackageFrameworks").path,
            "-Xcc", "-fmodule-map-file=\(shims.appending(path: "module.modulemap").path)",
            sourceURL.path, "-o", directory.appending(path: "Contract.o").path,
        ]
        let compiler = CommandLineTool(candidates: [executable], timeout: .seconds(30))
        let status = try await compiler.session(arguments) { streams in
            var streams = streams
            return try await streams.first { String(bytes: $0, encoding: .utf8).flatMap { Int32($0) } }
        }
        return (status, try String(contentsOf: diagnosticsURL, encoding: .utf8))
    }
}

func makeTestExecutable(in directory: URL, script: String) throws -> URL {
    let executable = directory.appending(path: UUID().uuidString)
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return executable
}

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

func allocatedHeapBytes() -> Int {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(malloc_default_zone(), &statistics)
    return statistics.size_in_use
}

final class Counter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    @discardableResult
    func increment() -> Int {
        count.withLock {
            $0 += 1
            return $0
        }
    }
}
