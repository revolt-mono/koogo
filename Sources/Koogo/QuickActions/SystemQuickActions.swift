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

    // NSAppleScript is main-thread-only; osascript keeps the blocking Apple event off the main actor.
    @concurrent
    static func toggleSystemAppearance() async throws {
        let process = Process()
        let errorOutput = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorOutput
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { process in
                guard process.terminationStatus == 0 else {
                    let details = (try? errorOutput.fileHandleForReading.readToEnd()) ?? Data()
                    let message =
                        String(bytes: details, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(
                        throwing: Failure.systemAppearance(
                            message.isEmpty ? "Could not change the system appearance." : message
                        )
                    )
                    return
                }
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
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
    static func eject(_ diskImages: MountedDiskImages) async throws {
        for diskImage in diskImages.values {
            try NSWorkspace.shared.unmountAndEjectDevice(at: diskImage.mountURL)
        }
    }
}
