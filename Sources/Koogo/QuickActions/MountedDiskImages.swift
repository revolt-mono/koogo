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
        guard !wholeDiskID.isEmpty, isEjectable, deviceModel == "Disk Image" else { return nil }

        self.wholeDiskID = wholeDiskID
        name =
            if let volumeName, !volumeName.isEmpty {
                volumeName
            } else {
                mountURL.lastPathComponent
            }
        self.mountURL = mountURL
    }
}

struct MountedDiskImages: Sendable {
    struct ScanFailure: LocalizedError {
        var errorDescription: String? { "Could not read mounted disk images." }
    }

    let values: [MountedDiskImage]

    /// Keeps one image per whole disk (the last scanned wins), sorted by name the way Finder sorts; nil when empty.
    init?(_ diskImages: [MountedDiskImage]) {
        let imagesByWholeDisk = Dictionary(diskImages.map { ($0.wholeDiskID, $0) }) { _, last in last }
        guard !imagesByWholeDisk.isEmpty else {
            return nil
        }
        values = imagesByWholeDisk.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// The visible disk images mounted right now; nil when there are none.
    @concurrent
    static func mounted() async throws -> MountedDiskImages? {
        guard
            let volumeURLs = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeNameKey, .volumeIsEjectableKey],
                options: .skipHiddenVolumes
            ),
            let session = DASessionCreate(kCFAllocatorDefault)
        else {
            throw ScanFailure()
        }

        var diskImages: [MountedDiskImage] = []
        for mountURL in volumeURLs {
            guard
                let values = try? mountURL.resourceValues(forKeys: [
                    .volumeNameKey,
                    .volumeIsEjectableKey,
                ]),
                let disk = DADiskCreateFromVolumePath(
                    kCFAllocatorDefault,
                    session,
                    mountURL as CFURL
                ),
                let wholeDisk = DADiskCopyWholeDisk(disk),
                let wholeDiskName = DADiskGetBSDName(wholeDisk),
                let diskImage = MountedDiskImage(
                    wholeDiskID: String(cString: wholeDiskName),
                    volumeName: values.volumeName,
                    mountURL: mountURL,
                    isEjectable: values.volumeIsEjectable == true,
                    deviceModel: (DADiskCopyDescription(wholeDisk) as? [String: Any])?[
                        kDADiskDescriptionDeviceModelKey as String
                    ] as? String
                )
            else {
                continue
            }

            diskImages.append(diskImage)
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
