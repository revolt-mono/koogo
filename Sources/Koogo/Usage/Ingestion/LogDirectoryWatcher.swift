import CoreServices
import Darwin
import Foundation
import Synchronization

/// filesystem events arrive asynchronously; syncs before delivery see changes on the next pass.
final class LogDirectoryWatcher {
    enum Changes {
        /// changed directories use the root paths supplied to the watcher.
        case directories(Set<String>)
        case everything
    }

    private final class Inbox: Sendable {
        private static let everythingFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged
                | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount
        )

        let roots: [(resolved: String, given: String)]
        private let changes = Mutex(Changes.directories([]))

        init(roots: [(resolved: String, given: String)]) {
            self.roots = roots
        }

        func record(_ path: String, flags: FSEventStreamEventFlags) {
            let directory = path.hasSuffix("/") ? String(path.dropLast()) : path
            let given = roots.lazy.compactMap { root -> String? in
                if directory == root.resolved {
                    return root.given
                }
                guard directory.hasPrefix(root.resolved + "/") else {
                    return nil
                }
                return root.given + directory.dropFirst(root.resolved.count)
            }.first
            changes.withLock { changes in
                guard case .directories(var directories) = changes, flags & Self.everythingFlags == 0, let given else {
                    changes = .everything
                    return
                }
                directories.insert(given)
                changes = .directories(directories)
            }
        }

        func take() -> Changes {
            changes.withLock { changes in
                defer { changes = .directories([]) }
                return changes
            }
        }
    }

    private let stream: FSEventStreamRef
    private let queue = DispatchQueue(label: "com.revolt.koogo.log-directories", qos: .utility)
    private let inbox: Inbox

    init?(roots: [String]) {
        inbox = Inbox(roots: roots.map { (Self.resolvingSymlinks($0), $0) })
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(inbox).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info, let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] else {
                return
            }
            let inbox = Unmanaged<Inbox>.fromOpaque(info).takeUnretainedValue()
            for index in 0..<count {
                inbox.record(paths[index], flags: flags[index])
            }
        }
        // zero latency avoids delayed delivery after a synchronous filesystem-event flush returns.
        guard
            let stream = FSEventStreamCreate(
                nil,
                callback,
                &context,
                inbox.roots.map(\.resolved) as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
            )
        else {
            return nil
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            return nil
        }
    }

    deinit {
        // stop on the callback queue so no callback can outlive the inbox.
        queue.sync {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
        }
        FSEventStreamRelease(stream)
    }

    /// retargeted symlinks can change resolved roots without a filesystem event.
    func watches(_ roots: [String]) -> Bool {
        inbox.roots.map(\.given) == roots && inbox.roots.allSatisfy { Self.resolvingSymlinks($0.given) == $0.resolved }
    }

    func takeChanges() -> Changes {
        inbox.take()
    }

    private static func resolvingSymlinks(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else {
            return path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
