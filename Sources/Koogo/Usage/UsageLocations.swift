import Foundation

struct UsageLocations: Sendable {
    struct Logs: Sendable {
        struct Codex: Sendable {
            let sessions: URL
            let archivedSessions: URL
        }

        let codex: Codex
        let claudeProjects: URL
        let piAgent: URL
    }

    struct PiModels: Sendable {
        let custom: URL
        let store: URL
    }

    let logs: Logs
    let piModels: PiModels

    static let standard: Self = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let piAgent = home.appending(path: ".pi/agent", directoryHint: .isDirectory)
        return Self(
            logs: Logs(
                codex: Logs.Codex(
                    sessions: home.appending(path: ".codex/sessions", directoryHint: .isDirectory),
                    archivedSessions: home.appending(
                        path: ".codex/archived_sessions",
                        directoryHint: .isDirectory
                    )
                ),
                claudeProjects: home.appending(
                    path: ".claude/projects",
                    directoryHint: .isDirectory
                ),
                piAgent: piAgent.appending(path: "sessions", directoryHint: .isDirectory)
            ),
            piModels: PiModels(
                custom: piAgent.appending(path: "models.json", directoryHint: .notDirectory),
                store: piAgent.appending(path: "models-store.json", directoryHint: .notDirectory)
            )
        )
    }()
}
