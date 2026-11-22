/// delivers complete lines once; a restart invalidates all state derived from previously consumed bytes.
protocol LogFile: Sendable {
  /// returns whether a read is due.
  mutating func observe(_ observed: UsageFileMetadata) -> Bool
  /// returns false when the consumer received nothing because the file could not be read; the next sync retries.
  mutating func read(restart: () -> Void, consume: (UnsafeRawBufferPointer) -> Void) -> Bool
}
