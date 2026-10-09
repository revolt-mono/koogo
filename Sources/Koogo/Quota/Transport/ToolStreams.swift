import Foundation
import Subprocess

struct ToolStreams {
    private static let lineLimit = 4 * 1_024 * 1_024

    private let input: StandardInputWriter
    private var lines: SubprocessOutputSequence.StringSequence<UTF8>.AsyncIterator

    init(input: StandardInputWriter, output: SubprocessOutputSequence) {
        self.input = input
        lines = output.strings(
            separatedBy: .unicodeScalarSequence(["\n"]),
            bufferingPolicy: .maxLineLength(Self.lineLimit)
        ).makeAsyncIterator()
    }

    func write(_ data: Data) async throws {
        _ = try await input.write(data)
    }

    /// Output that ends before `match` accepts a line means the tool closed without replying.
    mutating func first<Value>(_ match: (Data) throws -> Value?) async throws -> Value {
        while let line = try await lines.next() {
            if let value = try match(Data(line.utf8)) {
                return value
            }
        }
        throw ToolFailure.closed
    }
}
