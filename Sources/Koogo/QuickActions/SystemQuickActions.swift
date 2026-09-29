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

/// A claude, codex, or grok process whose parent exited, leaving it re-parented to launchd.
struct OrphanedAgentProcess: Sendable {
    enum Agent: String, CaseIterable {
        case claude, codex, grok
    }

    fileprivate let pid: pid_t
    let agent: Agent

    /// Recognizes the executable by name: codex runs as `codex`, grok as `grok-<version>-<platform>`, and
    /// claude as its bare version number inside a `claude` directory.
    init?(pid: pid_t, parentPID: pid_t, executablePath: String) {
        guard parentPID == 1 else { return nil }
        let executable = URL(filePath: executablePath)
        let name = executable.lastPathComponent
        if name == "codex" {
            agent = .codex
        } else if name.hasPrefix("grok") {
            agent = .grok
        } else if name.wholeMatch(of: /\d+\.\d+\.\d+/) != nil, executable.pathComponents.contains("claude") {
            agent = .claude
        } else {
            return nil
        }
        self.pid = pid
    }
}

struct OrphanedAgentProcesses: Sendable {
    let values: [OrphanedAgentProcess]

    /// Nil when empty.
    init?(_ processes: [OrphanedAgentProcess]) {
        guard !processes.isEmpty else {
            return nil
        }
        values = processes
    }

    /// Counts per agent, such as "2 claude, 1 codex".
    var summary: String {
        OrphanedAgentProcess.Agent.allCases.compactMap { agent in
            let count = values.count { $0.agent == agent }
            return count > 0 ? "\(count) \(agent.rawValue)" : nil
        }
        .joined(separator: ", ")
    }
}

enum SystemQuickActions {
    private enum Failure: LocalizedError {
        case diskImageScan
        case processScan
        case processTermination(OrphanedAgentProcess)
        case systemAppearance(String)

        var errorDescription: String? {
            switch self {
            case .diskImageScan:
                "Could not read mounted disk images."
            case .processScan:
                "Could not list running processes."
            case .processTermination(let process):
                "Could not stop \(process.agent.rawValue) process \(process.pid)."
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

    @concurrent
    static func orphanedAgentProcesses() async throws -> OrphanedAgentProcesses? {
        let pidStride = Int32(MemoryLayout<pid_t>.stride)
        let listedBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard listedBytes > 0 else { throw Failure.processScan }
        // Leave room for processes launched between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(listedBytes / pidStride) + 256)
        let filledBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count) * pidStride)
        guard filledBytes > 0 else { throw Failure.processScan }

        return OrphanedAgentProcesses(pids.prefix(Int(filledBytes / pidStride)).compactMap(orphanedAgentProcess))
    }

    /// The orphaned agent running as `pid` for the current user; nil once the pid is gone or runs something else.
    private static func orphanedAgentProcess(_ pid: pid_t) -> OrphanedAgentProcess? {
        var info = proc_bsdinfo()
        guard
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
            info.pbi_uid == getuid()
        else { return nil }
        var path = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = Int(proc_pidpath(pid, &path, UInt32(path.count)))
        guard pathLength > 0, let executablePath = String(bytes: path.prefix(pathLength), encoding: .utf8) else {
            return nil
        }
        return OrphanedAgentProcess(pid: pid, parentPID: pid_t(info.pbi_ppid), executablePath: executablePath)
    }

    /// Asks each process to exit, then kills whatever is still running two seconds later.
    @concurrent
    static func terminate(_ processes: OrphanedAgentProcesses) async throws {
        // A pid can be reused between the scan and the click; only signal processes that still match.
        var survivors = processes.values.filter { orphanedAgentProcess($0.pid) != nil }
        for process in survivors {
            try send(SIGTERM, to: process)
        }
        for _ in 0..<20 where !survivors.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
            survivors.removeAll { Darwin.kill($0.pid, 0) == -1 && errno == ESRCH }
        }
        for process in survivors {
            try send(SIGKILL, to: process)
        }
    }

    private static func send(_ signal: Int32, to process: OrphanedAgentProcess) throws {
        guard Darwin.kill(process.pid, signal) == 0 || errno == ESRCH else {
            throw Failure.processTermination(process)
        }
    }
}
