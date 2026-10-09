import Foundation
import XCTest

@testable import Koogo

final class CommandLineToolTests: XCTestCase {
    func testToolsRunWithAFixedEnvironmentInsteadOfTheAppsOwn() async throws {
        let root = try makeTemporaryDirectory()
        let executable = try makeTestExecutable(
            in: root,
            script: """
                #!/bin/sh
                printf '%s|%s|%s' "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "$USER" "$PATH"
                """
        )
        setenv("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1", 1)
        defer { unsetenv("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC") }

        let output = try await CommandLineTool(candidates: [executable], timeout: .seconds(3))
            .session([], in: root) { streams in
                try await streams.first { $0 }
            }
        let fields = try XCTUnwrap(String(bytes: output, encoding: .utf8)).split(
            separator: "|",
            omittingEmptySubsequences: false
        )

        XCTAssertEqual(fields.count, 3)
        XCTAssertEqual(fields[0], "")
        XCTAssertEqual(String(fields[1]), NSUserName())
        XCTAssertTrue(fields[2].hasPrefix("\(root.path):"))
        XCTAssertTrue(fields[2].contains(":/opt/homebrew/bin:"))
    }

    func testReplyNearTheDeadlineSurvivesASlowExit() async throws {
        let root = try makeTemporaryDirectory()
        let executable = try makeTestExecutable(
            in: root,
            script: """
                #!/bin/sh
                trap '' TERM
                sleep 0.2
                printf 'reply\\n'
                while :; do :; done
                """
        )

        let reply = try await CommandLineTool(candidates: [executable], timeout: .seconds(1))
            .session([], in: root) { streams in
                try await streams.first { $0 }
            }

        XCTAssertEqual(reply, Data("reply".utf8))
    }
}
