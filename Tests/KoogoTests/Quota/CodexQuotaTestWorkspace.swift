import Foundation

struct CodexQuotaTestWorkspace {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: root)
    }

    func makeExecutable(
        shebang: String = "#!/bin/sh",
        launchMarker: URL? = nil,
        responseDelay: TimeInterval = 0,
        rateLimitsResponse: String
    ) throws -> URL {
        let executable = root.appending(path: UUID().uuidString)
        let launchLine = launchMarker.map { "printf 'launch\\n' >> '\($0.path)'" } ?? ":"
        let script = """
            \(shebang)
            \(launchLine)
            IFS= read -r initialize
            printf '%s\\n' '{"id":1,"result":{}}'
            IFS= read -r initialized
            IFS= read -r rate_limits
            printf '%s\\n' '{"method":"unrelated/notification","params":{}}'
            sleep \(responseDelay)
            printf '%s\\n' '\(rateLimitsResponse)'
            """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return executable
    }
}
