import Foundation

@main
enum KoogoMain {
    static func main() async {
        guard CommandLine.arguments.contains("--report") else {
            KoogoApp.main()
            return
        }
        do {
            var output = try await SystemReport.generate()
            output.append(0x0A)
            FileHandle.standardOutput.write(output)
        } catch {
            FileHandle.standardError.write(Data("report failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
