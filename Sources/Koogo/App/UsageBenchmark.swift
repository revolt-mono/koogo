import CryptoKit
import Darwin
import Foundation

enum UsageBenchmark {
    private struct Phase: Encodable {
        let instructions: UInt64
        let milliseconds: Int
        let footprintBytes: UInt64
        /// Process-wide high-water mark, including earlier phases.
        let peakFootprintBytes: UInt64
    }

    private struct Result: Encodable {
        let digest: String
        let cold: Phase
        let unchanged: Phase
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
        let startInstructions = resourceUsage().ri_instructions
        let started = ContinuousClock.now
        let report = await work()
        let usage = resourceUsage()
        let phase = Phase(
            instructions: usage.ri_instructions - startInstructions,
            milliseconds: Int((ContinuousClock.now - started) / .milliseconds(1)),
            footprintBytes: usage.ri_phys_footprint,
            peakFootprintBytes: usage.ri_lifetime_max_phys_footprint
        )
        return (phase, report)
    }

    private static func resourceUsage() -> rusage_info_v4 {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        precondition(status == 0, "a process can always read its own resource usage")
        return usage
    }
}
