import Foundation

nonisolated enum StoryFormat: String, Sendable {
  case zMachine
  case glulx
}

/// Identifies a story file's format from its header bytes.
///
/// - Raw Z-machine files start with a single version byte (1–8).
/// - Raw Glulx files start with the four-byte magic `Glul`.
/// - Blorb-wrapped games start with `FORM` … `IFRS` (an IFF-style
///   resource container). Inside, the Exec chunk's type identifies the
///   VM: `ZCOD` for Z-machine, `GLUL` for Glulx.
///
/// For blorbs we parse the resource index (`RIdx`, always near the front)
/// to find the `Exec` resource's absolute file offset, then read the chunk
/// type there. Image-heavy blorbs list `Pict` chunks before `Exec`, pushing
/// the executable far past any fixed header window, so a fixed-size scan
/// misses it; seeking to the RIdx-declared offset does not. We keep the
/// 4 KiB scan as a fallback for blorbs whose RIdx we can't parse.
nonisolated enum FormatDetector {
  static func detect(header: Data) -> StoryFormat? {
    let bytes = [UInt8](header)
    guard bytes.count >= 4 else { return nil }

    // Raw Z-machine
    if (1...8).contains(bytes[0]) {
      return .zMachine
    }

    // Raw Glulx
    if startsWith(bytes, magic: glulMagic) {
      return .glulx
    }

    // Blorb wrapper: FORM + length(4) + IFRS
    if bytes.count >= 12,
       startsWith(bytes, magic: formMagic),
       hasMagic(bytes, atOffset: 8, magic: ifrsMagic) {
      return scanBlorbForInnerVM(bytes)
    }

    return nil
  }

  static func detect(url: URL) throws -> StoryFormat? {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    // The RIdx (and the raw-file header) live at the front; 4 KiB covers them.
    guard let header = try handle.read(upToCount: 4096) else { return nil }
    let bytes = [UInt8](header)

    // For a FORM…IFRS blorb, parse the RIdx for the Exec resource's absolute
    // offset and seek there to read the chunk type. This handles image-heavy
    // blorbs whose Exec chunk sits far past the header window.
    if isBlorbHeader(bytes), let execStart = execChunkOffset(inBlorbHeader: bytes) {
      try handle.seek(toOffset: UInt64(execStart))
      if let typeBytes = try handle.read(upToCount: 4), typeBytes.count == 4 {
        let type = [UInt8](typeBytes)
        if hasMagic(type, atOffset: 0, magic: glulInnerMagic) { return .glulx }
        if hasMagic(type, atOffset: 0, magic: zcodMagic) { return .zMachine }
      }
    }

    // Raw files, and blorbs whose RIdx we couldn't parse, fall back to the
    // in-window detection (which scans the 4 KiB header for the VM magic).
    return detect(header: header)
  }

  /// Absolute file offset of the `Exec` resource's chunk, parsed from a blorb's
  /// resource index (`RIdx`), or nil if `bytes` isn't a blorb header, the RIdx
  /// is malformed/truncated, or there's no `Exec` entry. Pure and testable; the
  /// returned offset may point past `bytes`, so callers must seek to read there.
  static func execChunkOffset(inBlorbHeader bytes: [UInt8]) -> Int? {
    guard isBlorbHeader(bytes) else { return nil }
    // The RIdx must be the first chunk, at offset 12: type(4) + length(4) +
    // count(4), then `count` entries of usage(4) + resnum(4) + start(4).
    guard hasMagic(bytes, atOffset: 12, magic: ridxMagic) else { return nil }
    guard let count = bigEndianUInt32(bytes, atOffset: 20) else { return nil }
    let firstEntry = 24
    for index in 0..<Int(count) {
      let entry = firstEntry + index * 12
      guard entry + 12 <= bytes.count else { return nil }
      if hasMagic(bytes, atOffset: entry, magic: execMagic),
         let start = bigEndianUInt32(bytes, atOffset: entry + 8) {
        return Int(start)
      }
    }
    return nil
  }

  /// Whether `bytes` opens with the `FORM` … `IFRS` blorb preamble.
  private static func isBlorbHeader(_ bytes: [UInt8]) -> Bool {
    bytes.count >= 12
      && startsWith(bytes, magic: formMagic)
      && hasMagic(bytes, atOffset: 8, magic: ifrsMagic)
  }

  /// Z-machine versions the bundled interpreter (ZVM) can run. v1/v2 are ancient
  /// and v6 is graphical; none are supported. (Glulx has no equivalent split.)
  static let supportedZMachineVersions: Set<UInt8> = [3, 4, 5, 8]

  /// The Z-machine version byte — raw file byte 0, or the first byte of a
  /// blorb's `ZCOD` chunk data (after its 4-byte type + 4-byte length). Nil if
  /// the header isn't a Z-machine story.
  static func zMachineVersion(header: Data) -> UInt8? {
    let bytes = [UInt8](header)
    guard bytes.count >= 4 else { return nil }
    if (1...8).contains(bytes[0]) { return bytes[0] }
    if bytes.count >= 12,
       startsWith(bytes, magic: formMagic),
       hasMagic(bytes, atOffset: 8, magic: ifrsMagic) {
      var offset = 12
      while offset + 8 < bytes.count {
        if hasMagic(bytes, atOffset: offset, magic: zcodMagic) {
          return bytes[offset + 8]
        }
        offset += 1
      }
    }
    return nil
  }

  // MARK: - Magic constants

  private static let glulMagic: [UInt8] = [0x47, 0x6C, 0x75, 0x6C]  // "Glul"
  private static let formMagic: [UInt8] = [0x46, 0x4F, 0x52, 0x4D]  // "FORM"
  private static let ifrsMagic: [UInt8] = [0x49, 0x46, 0x52, 0x53]  // "IFRS"
  private static let ridxMagic: [UInt8] = [0x52, 0x49, 0x64, 0x78]  // "RIdx"
  private static let execMagic: [UInt8] = [0x45, 0x78, 0x65, 0x63]  // "Exec"
  private static let zcodMagic: [UInt8] = [0x5A, 0x43, 0x4F, 0x44]  // "ZCOD"
  private static let glulInnerMagic: [UInt8] = [0x47, 0x4C, 0x55, 0x4C]  // "GLUL"

  // MARK: - Helpers

  private static func startsWith(_ bytes: [UInt8], magic: [UInt8]) -> Bool {
    hasMagic(bytes, atOffset: 0, magic: magic)
  }

  private static func hasMagic(_ bytes: [UInt8], atOffset offset: Int, magic: [UInt8]) -> Bool {
    guard offset + magic.count <= bytes.count else { return false }
    for index in 0..<magic.count where bytes[offset + index] != magic[index] {
      return false
    }
    return true
  }

  /// The big-endian 32-bit value at `offset`, or nil if it doesn't fit.
  private static func bigEndianUInt32(_ bytes: [UInt8], atOffset offset: Int) -> UInt32? {
    guard offset + 4 <= bytes.count else { return nil }
    return (UInt32(bytes[offset]) << 24)
      | (UInt32(bytes[offset + 1]) << 16)
      | (UInt32(bytes[offset + 2]) << 8)
      | UInt32(bytes[offset + 3])
  }

  /// Linear scan of the blorb header for the inner VM chunk's type
  /// magic. Starts after the FORM/IFRS preamble. The first match wins;
  /// a single blorb wraps a single VM, so collisions don't happen in
  /// practice (text content using "GLUL"/"ZCOD" as ASCII would have to
  /// appear before the Exec chunk's own magic, which is virtually never).
  private static func scanBlorbForInnerVM(_ bytes: [UInt8]) -> StoryFormat? {
    let limit = bytes.count - 4
    var offset = 12
    while offset <= limit {
      if hasMagic(bytes, atOffset: offset, magic: glulInnerMagic) {
        return .glulx
      }
      if hasMagic(bytes, atOffset: offset, magic: zcodMagic) {
        return .zMachine
      }
      offset += 1
    }
    return nil
  }
}
