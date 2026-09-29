import Foundation
import XCTest

@testable import Koogo

final class QuickActionsTests: XCTestCase {
    func testMountedDiskImageAcceptsOnlyEjectableDiskImages() {
        let mountURL = URL(filePath: "/Volumes/Example")

        XCTAssertNotNil(
            MountedDiskImage(
                wholeDiskID: "disk4",
                volumeName: "Example",
                mountURL: mountURL,
                isEjectable: true,
                deviceModel: "Disk Image"
            )
        )
        XCTAssertNil(
            MountedDiskImage(
                wholeDiskID: "disk4",
                volumeName: "External Drive",
                mountURL: mountURL,
                isEjectable: true,
                deviceModel: "External Physical Volume"
            )
        )
        XCTAssertNil(
            MountedDiskImage(
                wholeDiskID: "disk4",
                volumeName: "System Image",
                mountURL: mountURL,
                isEjectable: false,
                deviceModel: "Disk Image"
            )
        )
    }

    func testMountedDiskImagesIsNilWhenEmpty() {
        XCTAssertNil(MountedDiskImages([]))
    }

    func testMountedDiskImageNameFallsBackToMountDirectory() {
        let names = [nil, ""].map { volumeName in
            MountedDiskImage(
                wholeDiskID: "disk4",
                volumeName: volumeName,
                mountURL: URL(filePath: "/Volumes/Example"),
                isEjectable: true,
                deviceModel: "Disk Image"
            )?.name
        }

        XCTAssertEqual(names, ["Example", "Example"])
    }

    func testMountedDiskImagesKeepsLastImagePerWholeDisk() throws {
        let diskImages = MountedDiskImages([
            try diskImage(wholeDiskID: "disk4", name: "First Volume"),
            try diskImage(wholeDiskID: "disk5", name: "Other"),
            try diskImage(wholeDiskID: "disk4", name: "Last Volume"),
        ])

        XCTAssertEqual(diskImages?.values.map(\.name), ["Last Volume", "Other"])
    }

    func testMountedDiskImagesSortsNamesInLocalizedStandardOrder() throws {
        let diskImages = MountedDiskImages([
            try diskImage(wholeDiskID: "disk4", name: "Disk 10"),
            try diskImage(wholeDiskID: "disk5", name: "Disk 2"),
        ])

        XCTAssertEqual(diskImages?.values.map(\.name), ["Disk 2", "Disk 10"])
    }

    func testOrphanedAgentProcessRecognizesAgentExecutablesReparentedToLaunchd() {
        let orphans = [
            "/Users/me/.local/share/claude/versions/2.1.284",
            "/Users/me/.codex/packages/standalone/releases/0.158.0-aarch64-apple-darwin/bin/codex",
            "/Users/me/.grok/downloads/grok-1.0.45-macos-aarch64",
        ].map { OrphanedAgentProcess(pid: 42, parentPID: 1, executablePath: $0)?.agent }

        XCTAssertEqual(orphans, [.claude, .codex, .grok])
        XCTAssertNil(
            OrphanedAgentProcess(
                pid: 42,
                parentPID: 900,
                executablePath: "/Users/me/.local/share/claude/versions/2.1.284"
            )
        )
        XCTAssertNil(OrphanedAgentProcess(pid: 42, parentPID: 1, executablePath: "/opt/tool/versions/2.1.284"))
        XCTAssertNil(OrphanedAgentProcess(pid: 42, parentPID: 1, executablePath: "/Users/me/.local/share/claude/node"))
    }

    func testOrphanedAgentProcessesIsNilWhenEmpty() {
        XCTAssertNil(OrphanedAgentProcesses([]))
    }

    func testOrphanedAgentProcessesSummarizesCountsPerAgentInOrder() throws {
        let processes = OrphanedAgentProcesses([
            try orphan(pid: 7, executablePath: "/Users/me/.codex/bin/codex"),
            try orphan(pid: 5, executablePath: "/Users/me/.local/share/claude/versions/2.1.284"),
            try orphan(pid: 3, executablePath: "/Users/me/.codex/bin/codex"),
        ])

        XCTAssertEqual(processes?.summary, "1 claude, 2 codex")
    }

    private func orphan(pid: pid_t, executablePath: String) throws -> OrphanedAgentProcess {
        try XCTUnwrap(OrphanedAgentProcess(pid: pid, parentPID: 1, executablePath: executablePath))
    }

    private func diskImage(wholeDiskID: String, name: String) throws -> MountedDiskImage {
        try XCTUnwrap(
            MountedDiskImage(
                wholeDiskID: wholeDiskID,
                volumeName: name,
                mountURL: URL(filePath: "/Volumes/\(name)"),
                isEjectable: true,
                deviceModel: "Disk Image"
            )
        )
    }
}
