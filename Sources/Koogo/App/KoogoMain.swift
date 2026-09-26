import Foundation

@main
enum KoogoMain {
    static func main() async {
        let arguments = CommandLine.arguments
        let command: () async throws -> Data
        if arguments.contains("--report") {
            command = { try await SystemReport.generate() }
        } else if let flag = arguments.firstIndex(of: "--benchmark") {
            let home =
                arguments.dropFirst(flag + 1).first.map { URL(filePath: $0, directoryHint: .isDirectory) }
                ?? UsageLocations.standard.home
            command = { try await UsageBenchmark.run(home: home) }
        } else {
            KoogoApp.main()
            return
        }
        do {
            var output = try await command()
            output.append(0x0A)
            FileHandle.standardOutput.write(output)
        } catch {
            FileHandle.standardError.write(Data("failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
