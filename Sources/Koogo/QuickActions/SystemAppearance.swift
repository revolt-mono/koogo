import Foundation
import Subprocess

enum SystemAppearance {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    // osascript keeps blocking apple events off the main actor; in-process apple scripts require the main thread.
    static func toggle() async throws {
        let result = try await run(
            .path("/usr/bin/osascript"),
            arguments: [
                "-e",
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
            ],
            output: .discarded,
            error: .string(limit: 4_096)
        )
        guard result.terminationStatus.isSuccess else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(errorDescription: message.isEmpty ? "Could not change the system appearance." : message)
        }
    }
}
