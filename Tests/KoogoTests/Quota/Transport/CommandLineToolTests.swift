import Foundation
import Testing

@testable import Koogo

struct CommandLineToolTests {
  @Test
  func `only a successful lookup with a known country can authorize a provider`() async throws {
    for (status, body) in [
      (429, #"{"country":"SG"}"#),
      (200, "<html>Sign in</html>"),
      (200, #"{"country":null}"#),
    ] + ["XX", "T1", "001", "EU", "cn", " SG"].map({ (200, #"{"country":"\#($0)"}"#) }) {
      let access = ProviderUpstreamAccess { try ProviderUpstreamAccess.response(body, status: status) }
      await #expect(throws: ProviderUpstreamAccess.Denial.unknownRegion) { try await access.verify() }
    }
    for country in ["HK", "MO", "TW"] {
      let access = ProviderUpstreamAccess { try ProviderUpstreamAccess.response(#"{"country":"\#(country)"}"#) }
      try await access.verify()
    }
  }

  @Test
  func `canceling a lookup stops the launch without reporting a region denial`() async throws {
    let lookups = Counter()
    let access = ProviderUpstreamAccess {
      lookups.increment()
      try await Task.sleep(for: .seconds(5))
      return try ProviderUpstreamAccess.response(#"{"country":"SG"}"#)
    }
    let workspace = GrokQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let tool = try CommandLineTool(candidates: [workspace.makeAgent()], access: access)

    let reading = Task { await GrokQuotaSource(tool: tool).load() }
    try await Poll.until { lookups.value > 0 }
    reading.cancel()

    #expect(await reading.value == .unavailable(.sessionFailed))
    #expect(!FileManager.default.fileExists(atPath: workspace.argumentsFile.path))
  }

  @Test
  func `tools run in an empty directory with a fixed environment instead of the apps own`() async throws {
    let root = try scratch.makeTemporaryDirectory()
    let executable = try TestExecutable.make(
      in: root,
      script: """
        #!/bin/sh
        printf '%s|%s|%s|%s' "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "$USER" "$PATH" "$(pwd -P)"
        """,
    )
    setenv("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1", 1)
    defer { unsetenv("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC") }

    let output = try await CommandLineTool(candidates: [executable], timeout: .seconds(3))
      .session([]) { streams in
        var streams = streams
        return try await streams.first { $0 }
      }
    let fields = try #require(String(bytes: output, encoding: .utf8)).split(
      separator: "|",
      omittingEmptySubsequences: false,
    )

    #expect(fields.count == 4)
    #expect(fields[0] == "")
    #expect(String(fields[1]) == NSUserName())
    #expect(fields[2].hasPrefix("\(root.path):"))
    #expect(fields[2].contains(":/opt/homebrew/bin:"))
    try #expect(FileManager.default.contentsOfDirectory(atPath: String(fields[3])) == [])
  }

  @Test
  func `reply near the deadline survives a slow exit`() async throws {
    let root = try scratch.makeTemporaryDirectory()
    let executable = try TestExecutable.make(
      in: root,
      script: """
        #!/bin/sh
        trap '' TERM
        sleep 0.2
        printf 'reply\\n'
        while :; do :; done
        """,
    )

    let reply = try await CommandLineTool(candidates: [executable], timeout: .seconds(1))
      .session([]) { streams in
        var streams = streams
        return try await streams.first { $0 }
      }

    #expect(reply == Data("reply".utf8))
  }

  private let scratch = Scratch()
}
