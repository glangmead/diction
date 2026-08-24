import Compression
import Foundation

/// A minimal, read-only ZIP extractor — just enough to pull a single story file out
/// of an IFDB game archive. It reads the **central directory** for entry metadata (so
/// it gets correct sizes even for entries written with a streamed data descriptor),
/// copies stored entries (method 0), and inflates DEFLATE entries (method 8) via the
/// Compression framework (`COMPRESSION_ZLIB` decodes the raw DEFLATE that ZIP uses).
///
/// Deliberately NOT a general ZIP library: no zip64, encryption, or multi-disk
/// archives — IFDB's game zips don't use them. Anything it can't read throws, so the
/// caller surfaces "no download" instead of crashing. See `ZipStoryExtractor`.
nonisolated enum ZipArchive {
  enum ZipError: Error { case notZip, unsupported, badEntry, inflateFailed, tooLarge }

  /// One file entry, read from the central directory.
  struct Entry {
    let name: String
    let method: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
  }

  /// Guard against a malformed/hostile archive claiming a huge uncompressed size;
  /// real story files (even media-heavy blorbs) sit well under this.
  private static let maxEntrySize = 64 * 1024 * 1024

  private static let eocdSignature: UInt32 = 0x0605_4b50
  private static let centralSignature: UInt32 = 0x0201_4b50
  private static let localSignature: UInt32 = 0x0403_4b50

  /// Parse the central directory and return every file entry.
  static func entries(in bytes: [UInt8]) throws -> [Entry] {
    guard let eocd = findEOCD(in: bytes) else { throw ZipError.notZip }
    let count = Int(readU16(bytes, eocd + 10))
    var offset = Int(readU32(bytes, eocd + 16))   // start of the central directory
    var result: [Entry] = []
    for _ in 0..<count {
      guard offset + 46 <= bytes.count, readU32(bytes, offset) == centralSignature else {
        throw ZipError.badEntry
      }
      let nameLen = Int(readU16(bytes, offset + 28))
      let extraLen = Int(readU16(bytes, offset + 30))
      let commentLen = Int(readU16(bytes, offset + 32))
      let nameStart = offset + 46
      guard nameStart + nameLen <= bytes.count else { throw ZipError.badEntry }
      result.append(Entry(
        name: String(bytes: bytes[nameStart..<nameStart + nameLen], encoding: .utf8) ?? "",
        method: readU16(bytes, offset + 10),
        compressedSize: Int(readU32(bytes, offset + 20)),
        uncompressedSize: Int(readU32(bytes, offset + 24)),
        localHeaderOffset: Int(readU32(bytes, offset + 42))))
      offset = nameStart + nameLen + extraLen + commentLen
    }
    return result
  }

  /// Extract one entry's uncompressed bytes.
  static func extract(_ entry: Entry, from bytes: [UInt8]) throws -> Data {
    guard entry.uncompressedSize <= maxEntrySize else { throw ZipError.tooLarge }
    let base = entry.localHeaderOffset
    guard base + 30 <= bytes.count, readU32(bytes, base) == localSignature else {
      throw ZipError.badEntry
    }
    // The local header repeats name/extra lengths, which can differ from the central
    // directory's, so the data offset must use the local copies.
    let nameLen = Int(readU16(bytes, base + 26))
    let extraLen = Int(readU16(bytes, base + 28))
    let dataStart = base + 30 + nameLen + extraLen
    guard dataStart + entry.compressedSize <= bytes.count else { throw ZipError.badEntry }
    let compressed = Array(bytes[dataStart..<dataStart + entry.compressedSize])
    switch entry.method {
    case 0: return Data(compressed)                                   // stored
    case 8: return try inflate(compressed, expectedSize: entry.uncompressedSize)  // deflate
    default: throw ZipError.unsupported
    }
  }

  // MARK: - Internals

  /// Scan backward for the End Of Central Directory signature. The record sits within
  /// the final 22 bytes plus an optional comment (rare and short for game zips).
  private static func findEOCD(in bytes: [UInt8]) -> Int? {
    guard bytes.count >= 22 else { return nil }
    let minStart = max(0, bytes.count - 22 - 0xFFFF)
    var index = bytes.count - 22
    while index >= minStart {
      if readU32(bytes, index) == eocdSignature { return index }
      index -= 1
    }
    return nil
  }

  private static func inflate(_ compressed: [UInt8], expectedSize: Int) throws -> Data {
    guard expectedSize > 0 else { return Data() }
    guard expectedSize <= maxEntrySize else { throw ZipError.tooLarge }
    let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
    defer { destination.deallocate() }
    let written = compressed.withUnsafeBufferPointer { source in
      compression_decode_buffer(
        destination, expectedSize,
        source.baseAddress!, source.count,
        nil, COMPRESSION_ZLIB)
    }
    guard written == expectedSize else { throw ZipError.inflateFailed }
    return Data(bytes: destination, count: written)
  }

  private static func readU16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
  }

  private static func readU32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
      | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
  }
}
