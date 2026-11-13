import Foundation
import Subprocess

struct ToolStreams: ~Copyable {
  init(input: StandardInputWriter, output: SubprocessOutputSequence) {
    self.input = input
    lines = output.strings(
      separatedBy: .unicodeScalarSequence(["\n"]),
      bufferingPolicy: .maxLineLength(Self.lineLimit),
    ).makeAsyncIterator()
  }

  func write(_ data: Data) async throws {
    _ = try await input.write(data)
  }

  mutating func first<Value>(_ match: (Data) throws -> Value?) async throws -> Value {
    do {
      while let line = try await lines.next() {
        if let value = try match(Data(line.utf8)) {
          return value
        }
      }
    } catch is DecodingError {
      throw ToolFailure.invalidMessage
    } catch let error as SubprocessError where error.code == .outputLimitExceeded {
      throw ToolFailure.invalidMessage
    }
    throw ToolFailure.closed
  }

  private static let lineLimit = 4 * 1_024 * 1_024

  private let input: StandardInputWriter
  private var lines: SubprocessOutputSequence.StringSequence<UTF8>.AsyncIterator
}
