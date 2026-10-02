import Darwin
import Foundation

enum LogMatch: Sendable {
    case fileExtension(String)
    case fileName(String)

    func matches(path: String) -> Bool {
        switch self {
        case .fileExtension(let suffix): path.hasSuffix(suffix)
        case .fileName(let name): path.hasSuffix("/" + name)
        }
    }
}

struct UsageLogRoot: Sendable {
    let provider: Provider
    let url: URL
    let match: LogMatch
}

enum LogDiscovery {
    /// Visits every matching regular file under the root, skipping hidden entries below it.
    static func walk(_ root: UsageLogRoot, _ body: (String, UsageFileMetadata) -> Void) {
        var paths: [UnsafeMutablePointer<CChar>?] = [strdup(root.url.path), nil]
        defer { free(paths[0]) }
        guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_COMFOLLOW | FTS_NOCHDIR, nil) else {
            return
        }
        defer { fts_close(stream) }
        while let entry = fts_read(stream) {
            let info = Int32(entry.pointee.fts_info)
            let status = entry.pointee.fts_statp.pointee
            let isHidden =
                entry.pointee.fts_name == CChar(UInt8(ascii: ".")) || status.st_flags & UInt32(UF_HIDDEN) != 0
            if entry.pointee.fts_level > 0, isHidden {
                if info == FTS_D {
                    fts_set(stream, entry, FTS_SKIP)
                }
                continue
            }
            guard info == FTS_F, let metadata = UsageFileMetadata(status: status) else {
                continue
            }
            let path = String(cString: entry.pointee.fts_path)
            if root.match.matches(path: path) {
                body(path, metadata)
            }
        }
    }
}
