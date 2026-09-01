import AppKit
import DiskArbitration

struct MountedDiskImage: Sendable {
    fileprivate let wholeDiskID: String
    let name: String
    fileprivate let mountURL: URL

    init?(
        wholeDiskID: String?,
        volumeName: String?,
        mountURL: URL,
        isEjectable: Bool,
        deviceModel: String?
    ) {
        guard
            let wholeDiskID,
            !wholeDiskID.isEmpty,
            isEjectable,
            deviceModel == "Disk Image"
        else {
            return nil
        }

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
    let values: [MountedDiskImage]

    init?(_ diskImages: [MountedDiskImage]) {
        guard !diskImages.isEmpty else {
            return nil
        }
        values = diskImages
    }
}

enum SystemQuickActions {
    private enum Failure: LocalizedError {
        case diskImageScan
        case systemAppearance(String)

        var errorDescription: String? {
            switch self {
            case .diskImageScan:
                "Could not read mounted disk images."
            case .systemAppearance(let message):
                message
            }
        }
    }

    @concurrent
    static func toggleSystemAppearance() async throws {
        guard
            let script = NSAppleScript(
                source: """
                    tell application "System Events"
                        tell appearance preferences
                            set dark mode to not dark mode
                        end tell
                    end tell
                    """
            )
        else {
            throw Failure.systemAppearance("Could not prepare the system appearance action.")
        }

        var details: NSDictionary?
        _ = script.executeAndReturnError(&details)
        if let details {
            throw Failure.systemAppearance(
                details[NSAppleScript.errorMessage] as? String
                    ?? "Could not change the system appearance."
            )
        }
    }

    @concurrent
    static func mountedDiskImages() async throws -> MountedDiskImages? {
        guard
            let volumeURLs = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeNameKey, .volumeIsEjectableKey],
                options: .skipHiddenVolumes
            ),
            let session = DASessionCreate(kCFAllocatorDefault)
        else {
            throw Failure.diskImageScan
        }

        var diskImages: [String: MountedDiskImage] = [:]
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

            diskImages[diskImage.wholeDiskID] = diskImage
        }

        return MountedDiskImages(
            diskImages.values.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        )
    }

    @concurrent
    static func eject(_ diskImages: MountedDiskImages) async throws {
        for diskImage in diskImages.values {
            try NSWorkspace.shared.unmountAndEjectDevice(at: diskImage.mountURL)
        }
    }
}
