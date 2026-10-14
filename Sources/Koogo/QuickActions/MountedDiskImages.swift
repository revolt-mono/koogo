import AppKit
import DiskArbitration

struct MountedDiskImage: Sendable {
    fileprivate let wholeDiskID: String
    let name: String
    fileprivate let mountURL: URL

    init?(
        wholeDiskID: String,
        volumeName: String?,
        mountURL: URL,
        isEjectable: Bool,
        deviceModel: String?
    ) {
        guard isEjectable, deviceModel == "Disk Image" else { return nil }

        self.wholeDiskID = wholeDiskID
        name = volumeName?.nonEmpty ?? mountURL.lastPathComponent
        self.mountURL = mountURL
    }
}

struct MountedDiskImages: Sendable {
    struct ScanFailure: LocalizedError {
        var errorDescription: String? { "Could not read mounted disk images." }
    }

    let values: [MountedDiskImage]

    init?(_ diskImages: [MountedDiskImage]) {
        let imagesByWholeDisk = Dictionary(diskImages.map { ($0.wholeDiskID, $0) }) { _, last in last }
        guard !imagesByWholeDisk.isEmpty else {
            return nil
        }
        values = imagesByWholeDisk.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @concurrent
    static func mounted() async throws -> MountedDiskImages? {
        let volumeKeys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsEjectableKey]
        guard
            let volumeURLs = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: Array(volumeKeys),
                options: .skipHiddenVolumes
            ),
            let session = DASessionCreate(kCFAllocatorDefault)
        else {
            throw ScanFailure()
        }

        let diskImages = volumeURLs.compactMap { mountURL -> MountedDiskImage? in
            guard
                let values = try? mountURL.resourceValues(forKeys: volumeKeys),
                let disk = DADiskCreateFromVolumePath(
                    kCFAllocatorDefault,
                    session,
                    mountURL as CFURL
                ),
                let wholeDisk = DADiskCopyWholeDisk(disk),
                let wholeDiskName = DADiskGetBSDName(wholeDisk)
            else {
                return nil
            }
            return MountedDiskImage(
                wholeDiskID: String(cString: wholeDiskName),
                volumeName: values.volumeName,
                mountURL: mountURL,
                isEjectable: values.volumeIsEjectable == true,
                deviceModel: (DADiskCopyDescription(wholeDisk) as? [String: Any])?[
                    kDADiskDescriptionDeviceModelKey as String
                ] as? String
            )
        }
        return MountedDiskImages(diskImages)
    }

    @concurrent
    func eject() async throws {
        for diskImage in values {
            try NSWorkspace.shared.unmountAndEjectDevice(at: diskImage.mountURL)
        }
    }
}
