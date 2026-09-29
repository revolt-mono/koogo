import Foundation

enum SystemAppearance {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    // NSAppleScript is main-thread-only; osascript keeps the blocking Apple event off the main actor.
    @concurrent
    static func toggle() async throws {
        let process = Process()
        let errorOutput = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorOutput
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { process in
                guard process.terminationStatus == 0 else {
                    let details = (try? errorOutput.fileHandleForReading.readToEnd()) ?? Data()
                    let message =
                        String(bytes: details, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(
                        throwing: Failure(
                            errorDescription: message.isEmpty ? "Could not change the system appearance." : message
                        )
                    )
                    return
                }
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
