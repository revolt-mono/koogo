/// Why a quota read through a local CLI shows nothing; surfaced in telemetry and the `--report` output.
enum CLIQuotaUnavailability: String, Error, Encodable, Sendable {
    case binaryNotFound
    case timedOut
    case sessionFailed
    case emptyLimits

    init(_ error: any Error) {
        self =
            switch error {
            case CommandLineTool.Failure.notFound: .binaryNotFound
            case CommandLineTool.Failure.timedOut: .timedOut
            default: .sessionFailed
            }
    }
}
