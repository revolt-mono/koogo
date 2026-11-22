import Foundation
import Testing

@testable import Koogo

struct MountedDiskImagesTests {
  @Test
  func `mounted disk image accepts only ejectable disk images`() {
    let mountURL = URL(filePath: "/Volumes/Example")

    #expect(
      MountedDiskImage(
        wholeDiskID: "disk4",
        volumeName: "Example",
        mountURL: mountURL,
        isEjectable: true,
        deviceModel: "Disk Image",
      )
        != nil
    )
    #expect(
      MountedDiskImage(
        wholeDiskID: "disk4",
        volumeName: "External Drive",
        mountURL: mountURL,
        isEjectable: true,
        deviceModel: "External Physical Volume",
      )
        == nil
    )
    #expect(
      MountedDiskImage(
        wholeDiskID: "disk4",
        volumeName: "System Image",
        mountURL: mountURL,
        isEjectable: false,
        deviceModel: "Disk Image",
      )
        == nil
    )
  }

  @Test
  func `mounted disk image name falls back to mount directory`() {
    let names = [nil, ""].map { volumeName in
      MountedDiskImage(
        wholeDiskID: "disk4",
        volumeName: volumeName,
        mountURL: URL(filePath: "/Volumes/Example"),
        isEjectable: true,
        deviceModel: "Disk Image",
      )?.name
    }

    #expect(names == ["Example", "Example"])
  }

  @Test
  func `mounted disk images keeps last image per whole disk`() throws {
    let diskImages = MountedDiskImages([
      try diskImage(wholeDiskID: "disk4", name: "First Volume"),
      try diskImage(wholeDiskID: "disk5", name: "Other"),
      try diskImage(wholeDiskID: "disk4", name: "Last Volume"),
    ])

    #expect(diskImages?.values.map(\.name) == ["Last Volume", "Other"])
  }

  @Test
  func `mounted disk images sorts names in localized standard order`() throws {
    let diskImages = MountedDiskImages([
      try diskImage(wholeDiskID: "disk4", name: "Disk 10"),
      try diskImage(wholeDiskID: "disk5", name: "Disk 2"),
    ])

    #expect(diskImages?.values.map(\.name) == ["Disk 2", "Disk 10"])
  }

  private func diskImage(wholeDiskID: String, name: String) throws -> MountedDiskImage {
    try #require(
      MountedDiskImage(
        wholeDiskID: wholeDiskID,
        volumeName: name,
        mountURL: URL(filePath: "/Volumes/\(name)"),
        isEjectable: true,
        deviceModel: "Disk Image",
      )
    )
  }
}
