import Foundation
import XCTest

@testable import Koogo

final class QuickActionsTests: XCTestCase {
    private actor DummyDiskImageSystem {
        var diskImages: MountedDiskImages?

        init(diskImages: MountedDiskImages) {
            self.diskImages = diskImages
        }

        func mountedDiskImages() -> MountedDiskImages? {
            diskImages
        }

        func eject(_: MountedDiskImages) {
            diskImages = nil
        }
    }

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
        XCTAssertEqual(MountedDiskImages([diskImage])?.values.count, 1)
    }

    @MainActor
    func testEjectingAllDiskImagesFinishesWithNoneMounted() async throws {
        let diskImage = try XCTUnwrap(
            MountedDiskImage(
                wholeDiskID: "disk4",
                volumeName: "Example",
                mountURL: URL(filePath: "/Volumes/Example"),
                isEjectable: true,
                deviceModel: "Disk Image"
            )
        )
        let diskImages = try XCTUnwrap(MountedDiskImages([diskImage]))
        let dummy = DummyDiskImageSystem(diskImages: diskImages)
        let state = await MountedDiskImagesQuickAction.State.eject(
            diskImages,
            using: { await dummy.eject($0) },
            mountedDiskImages: { await dummy.mountedDiskImages() }
        )

        guard case .none = state else {
            return XCTFail("Expected no mounted disk images after ejecting.")
        }
    }
}
