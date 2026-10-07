import Foundation

struct LineReader {
    private static let outputLimit = 4 * 1_024 * 1_024

    private let fileHandle: FileHandle
    private var buffer = Data()

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    mutating func nextLine() throws -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                return line
            }
            let chunk = fileHandle.availableData
            if chunk.isEmpty {
                guard !buffer.isEmpty else {
                    return nil
                }
                defer { buffer.removeAll() }
                return buffer
            }
            buffer.append(chunk)
            guard buffer.count <= Self.outputLimit else {
                throw ToolFailure.invalidMessage
            }
        }
    }
}
