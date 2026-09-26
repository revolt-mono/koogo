import CryptoKit
import Darwin
import Foundation

/// `Koogo --benchmark [home]`: runs the usage refreshes behind the panel's journeys over the logs under `home`
/// and prints each one's cost as JSON. Retired instructions barely move between runs over the same logs, so they
/// are the number to compare across changes; an unchanged snapshot digest shows the change kept the output.
enum UsageBenchmark {
    private struct Phase: Encodable {
        let instructions: UInt64
        let milliseconds: Int
    }

    private struct Result: Encodable {
        /// SHA-256 of the cold snapshot's JSON.
        let digest: String
        /// First panel open after launch: every log in the history window is read.
        let cold: Phase
        /// Panel reopened with no log changes.
        let unchanged: Phase
        /// Panel reopened after a change: tracked events are merged and the snapshot rebuilt, here forced by
        /// moving the refresh one day forward.
        let rebuild: Phase
    }

    static func run(home: URL) async throws -> Data {
        let service = UsageService(locations: UsageLocations(home: home))
        let date = Date.now
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let (cold, report) = await measure { await service.refresh(at: date) }
        let result = Result(
            digest: SHA256.hash(data: try encoder.encode(report.snapshot)).map { String(format: "%02x", $0) }.joined(),
            cold: cold,
            unchanged: await measure { await service.refresh(at: date) }.phase,
            rebuild: await measure { await service.refresh(at: date.addingTimeInterval(86_400)) }.phase
        )
        return try encoder.encode(result)
    }

    private static func measure(_ work: () async -> UsageReport) async -> (phase: Phase, report: UsageReport) {
        let startInstructions = retiredInstructions()
        let started = ContinuousClock.now
        let report = await work()
        let phase = Phase(
            instructions: retiredInstructions() - startInstructions,
            milliseconds: Int((ContinuousClock.now - started) / .milliseconds(1))
        )
        return (phase, report)
    }

    /// Instructions retired by every thread of this process so far.
    private static func retiredInstructions() -> UInt64 {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        precondition(status == 0, "a process can always read its own resource usage")
        return usage.ri_instructions
    }
}
