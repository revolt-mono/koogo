import Foundation

struct JSONObjectReader {
  init?(_ bytes: UnsafeRawBufferPointer) {
    self.bytes = bytes
    offset = 0
    skipWhitespace()
    guard offset < bytes.count, bytes[offset] == UInt8(ascii: "{") else {
      return nil
    }
    offset += 1
  }

  struct Member {
    let key: JSONKey
    let value: JSONValue
  }

  mutating func next() throws(MalformedUsageRecord) -> Member? {
    skipWhitespace()
    guard offset < bytes.count else {
      throw MalformedUsageRecord()
    }
    switch bytes[offset] {
    case UInt8(ascii: "}"):
      guard bytes[(offset + 1)...].allSatisfy(Self.isWhitespace) else {
        throw MalformedUsageRecord()
      }
      return nil

    case UInt8(ascii: ",") where hasMember:
      offset += 1
      skipWhitespace()

    default:
      guard !hasMember else {
        throw MalformedUsageRecord()
      }
    }
    let keyStart = offset
    offset = try stringEnd(at: keyStart)
    let key = JSONKey(JSONValue(bytes: UnsafeRawBufferPointer(rebasing: bytes[keyStart..<offset])))
    skipWhitespace()
    guard offset < bytes.count, bytes[offset] == UInt8(ascii: ":") else {
      throw MalformedUsageRecord()
    }
    offset += 1
    skipWhitespace()
    let valueStart = offset
    offset = try valueEnd(at: valueStart)
    hasMember = true
    return Member(key: key, value: JSONValue(bytes: UnsafeRawBufferPointer(rebasing: bytes[valueStart..<offset])))
  }

  consuming func member(_ key: StaticString) throws(MalformedUsageRecord) -> JSONValue? {
    var value: JSONValue?
    while let member = try next() {
      if member.key.isString(key) {
        value = member.value
      }
    }
    return value
  }

  private let bytes: UnsafeRawBufferPointer
  private var offset: Int
  private var hasMember = false

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\t")
      || byte == UInt8(ascii: "\r")
  }

  private static func endsScalar(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: ",") || byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") || isWhitespace(byte)
  }

  private mutating func skipWhitespace() {
    while offset < bytes.count, Self.isWhitespace(bytes[offset]) {
      offset += 1
    }
  }

  private func valueEnd(at start: Int) throws(MalformedUsageRecord) -> Int {
    guard start < bytes.count else {
      throw MalformedUsageRecord()
    }
    switch bytes[start] {
    case UInt8(ascii: "\""):
      return try stringEnd(at: start)

    case UInt8(ascii: "{"),
         UInt8(ascii: "["):
      var depth = 0
      var index = start
      while index < bytes.count {
        switch bytes[index] {
        case UInt8(ascii: "\""):
          index = try stringEnd(at: index)
          continue

        case UInt8(ascii: "{"),
             UInt8(ascii: "["):
          depth += 1

        case UInt8(ascii: "}"),
             UInt8(ascii: "]"):
          depth -= 1
          if depth == 0 {
            return index + 1
          }

        default:
          break
        }
        index += 1
      }
      throw MalformedUsageRecord()

    default:
      var index = start
      while index < bytes.count, !Self.endsScalar(bytes[index]) {
        index += 1
      }
      guard index > start else {
        throw MalformedUsageRecord()
      }
      return index
    }
  }

  private func stringEnd(at start: Int) throws(MalformedUsageRecord) -> Int {
    guard start < bytes.count, bytes[start] == UInt8(ascii: "\""), let base = bytes.baseAddress else {
      throw MalformedUsageRecord()
    }
    var searchStart = start + 1
    while let quote = memchr(base + searchStart, Int32(UInt8(ascii: "\"")), bytes.count - searchStart) {
      let quoteIndex = base.distance(to: quote)
      var backslashes = 0
      while bytes[quoteIndex - 1 - backslashes] == UInt8(ascii: "\\") {
        backslashes += 1
      }
      if backslashes.isMultiple(of: 2) {
        return quoteIndex + 1
      }
      searchStart = quoteIndex + 1
    }
    throw MalformedUsageRecord()
  }
}

struct JSONKey {
  fileprivate init(_ value: JSONValue) {
    self.value = value
  }

  static func ~=(literal: StaticString, key: Self) -> Bool {
    key.isString(literal)
  }

  func isString(_ literal: StaticString) -> Bool {
    value.isString(literal)
  }

  func string() throws(MalformedUsageRecord) -> String {
    try value.string()!
  }

  private let value: JSONValue
}

enum JSONText: RandomAccessCollection {
  case logged(UnsafeRawBufferPointer)
  case decoded([UInt8])

  var startIndex: Int {
    0
  }

  var endIndex: Int {
    switch self {
    case .logged(let bytes): bytes.count
    case .decoded(let bytes): bytes.count
    }
  }

  subscript(position: Int) -> UInt8 {
    switch self {
    case .logged(let bytes): bytes[position]
    case .decoded(let bytes): bytes[position]
    }
  }

  func withContiguousStorageIfAvailable<Result>(
    _ body: (UnsafeBufferPointer<UInt8>) throws -> Result
  ) rethrows -> Result? {
    switch self {
    case .logged(let bytes): try bytes.withMemoryRebound(to: UInt8.self, body)
    case .decoded(let bytes): try bytes.withUnsafeBufferPointer(body)
    }
  }
}

/// borrows its bytes from the log line.
struct JSONValue {
  fileprivate init(bytes: UnsafeRawBufferPointer) {
    self.bytes = bytes
  }

  var isNull: Bool {
    bytes.elementsEqual("null".utf8)
  }

  var nonNull: Self? {
    isNull ? nil : self
  }

  static func ~=(literal: StaticString, value: Self) -> Bool {
    value.isString(literal)
  }

  /// literals hold no quotes or backslashes.
  func isString(_ literal: StaticString) -> Bool {
    let count = literal.utf8CodeUnitCount
    guard bytes.count == count + 2 else {
      return bytes.count > count + 2 && hasEscape && (try? string()) == literal.description
    }
    return bytes[0] == UInt8(ascii: "\"") && memcmp(bytes.baseAddress! + 1, literal.utf8Start, count) == 0
  }

  func object() throws(MalformedUsageRecord) -> JSONObjectReader {
    guard let object = JSONObjectReader(bytes) else {
      throw MalformedUsageRecord()
    }
    return object
  }

  func member(_ key: StaticString) throws(MalformedUsageRecord) -> JSONValue? {
    try object().member(key)
  }

  func text() throws(MalformedUsageRecord) -> JSONText? {
    guard !isNull else {
      return nil
    }
    return switch try stringContent() {
    case .unescaped(let content): .logged(content)
    case .decoded(let string): .decoded(Array(string.utf8))
    }
  }

  func string() throws(MalformedUsageRecord) -> String? {
    guard !isNull else {
      return nil
    }
    return switch try stringContent() {
    case .unescaped(let content): String(decoding: content, as: UTF8.self)
    case .decoded(let string): string
    }
  }

  func uint64() throws(MalformedUsageRecord) -> UInt64? {
    guard !isNull else {
      return nil
    }
    if let value = plainUInt64 {
      return value
    }
    return try foundationDecoded(as: UInt64.self)
  }

  /// reads nonnegative us dollars, rounded half up to whole picodollars.
  func usd() throws(MalformedUsageRecord) -> Picodollars? {
    guard !isNull else {
      return nil
    }
    guard isNumber, bytes.first != UInt8(ascii: "-") else {
      throw MalformedUsageRecord()
    }
    let mantissaEnd = bytes.firstIndex { $0 == UInt8(ascii: "e") || $0 == UInt8(ascii: "E") } ?? bytes.count
    var significand: UInt64 = 0
    var exponent = 12
    var isFraction = false
    for byte in bytes[..<mantissaEnd] {
      if byte == UInt8(ascii: ".") {
        isFraction = true
        continue
      }
      guard let next = Self.appending(digit: byte, to: significand) else {
        throw MalformedUsageRecord()
      }
      significand = next
      exponent -= isFraction ? 1 : 0
    }
    if mantissaEnd < bytes.count {
      var digits = bytes[(mantissaEnd + 1)...]
      let isNegative = digits.first == UInt8(ascii: "-")
      if isNegative || digits.first == UInt8(ascii: "+") {
        digits.removeFirst()
      }
      let written = digits.reduce(0) { min($0 * 10 + Int($1 - UInt8(ascii: "0")), 1_000) }
      exponent += isNegative ? -written : written
    }
    return try Self.picodollars(significand, timesTenToThe: exponent)
  }

  private enum StringContent {
    case unescaped(UnsafeRawBufferPointer)
    case decoded(String)
  }

  private let bytes: UnsafeRawBufferPointer

  private var plainUInt64: UInt64? {
    guard bytes.first != UInt8(ascii: "0") || bytes.count == 1 else {
      return nil
    }
    var value: UInt64 = 0
    for byte in bytes {
      guard Self.isDigit(byte), let next = Self.appending(digit: byte, to: value) else {
        return nil
      }
      value = next
    }
    return value
  }

  private var isNumber: Bool {
    var index = 0
    func skipDigits() -> Bool {
      let start = index
      while index < bytes.count, Self.isDigit(bytes[index]) {
        index += 1
      }
      return index > start
    }
    if index < bytes.count, bytes[index] == UInt8(ascii: "-") {
      index += 1
    }
    if index < bytes.count, bytes[index] == UInt8(ascii: "0") {
      index += 1
    } else if !skipDigits() {
      return false
    }
    if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
      index += 1
      guard skipDigits() else {
        return false
      }
    }
    if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
      index += 1
      if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
        index += 1
      }
      guard skipDigits() else {
        return false
      }
    }
    return index == bytes.count
  }

  private var hasEscape: Bool {
    memchr(bytes.baseAddress, Int32(UInt8(ascii: "\\")), bytes.count) != nil
  }

  private static func appending(digit byte: UInt8, to value: UInt64) -> UInt64? {
    let (tens, overflow) = value.multipliedReportingOverflow(by: 10)
    let (next, carry) = tens.addingReportingOverflow(UInt64(byte - UInt8(ascii: "0")))
    return overflow || carry ? nil : next
  }

  private static func picodollars(
    _ significand: UInt64,
    timesTenToThe exponent: Int,
  ) throws(MalformedUsageRecord) -> Picodollars {
    guard significand > 0, exponent > -20 else {
      return .zero
    }
    guard exponent < 0 else {
      var picodollars = significand
      for _ in 0..<exponent {
        let (scaled, overflow) = picodollars.multipliedReportingOverflow(by: 10)
        guard !overflow else {
          throw MalformedUsageRecord()
        }
        picodollars = scaled
      }
      return Picodollars(picodollars)
    }
    let divisor = (0 ..< -exponent).reduce(UInt64(1)) { power, _ in power * 10 }
    let (quotient, remainder) = significand.quotientAndRemainder(dividingBy: divisor)
    return Picodollars(remainder >= divisor - remainder ? quotient + 1 : quotient)
  }

  private static func isDigit(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
  }

  private static func isPlainASCII(_ byte: UInt8) -> Bool {
    byte >= 0x20 && byte < 0x7F && byte != UInt8(ascii: "\\")
  }

  private static func isValidUTF8(_ content: UnsafeRawBufferPointer) -> Bool {
    content.withMemoryRebound(to: UInt8.self) { (try? UTF8Span(validating: $0.span)) != nil }
  }

  private func foundationDecoded<Value: Decodable>(as _: Value.Type) throws(MalformedUsageRecord) -> Value {
    guard let value = try? JSONDecoder().decode(Value.self, from: Data(bytes)) else {
      throw MalformedUsageRecord()
    }
    return value
  }

  private func stringContent() throws(MalformedUsageRecord) -> StringContent {
    guard bytes.count >= 2, bytes[0] == UInt8(ascii: "\"") else {
      throw MalformedUsageRecord()
    }
    let content = UnsafeRawBufferPointer(rebasing: bytes[1..<bytes.count - 1])
    if content.allSatisfy(Self.isPlainASCII) {
      return .unescaped(content)
    }
    if hasEscape {
      return .decoded(try foundationDecoded(as: String.self))
    }
    guard !content.contains(where: { $0 < 0x20 }), Self.isValidUTF8(content) else {
      throw MalformedUsageRecord()
    }
    return .unescaped(content)
  }
}
