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
