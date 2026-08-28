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

    func testMountedDiskImagesRequiresAtLeastOneImage() throws {
        let diskImage = try XCTUnwrap(
            MountedDiskImage(
                wholeDiskID: "disk4",
                volumeName: "Example",
                mountURL: URL(filePath: "/Volumes/Example"),
                isEjectable: true,
                deviceModel: "Disk Image"
            )
        )

        XCTAssertNil(MountedDiskImages([]))
        XCTAssertEqual(MountedDiskImages([diskImage])?.count, 1)
    }
}
