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
/// We read up to 4 KiB of header and scan for the inner VM magic, which
/// works for any blorb whose Exec chunk lives in that window — true for
/// every game tested so far (the resource index and Exec chunk are
/// typically the first things after the FORM header).
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
    // 4 KiB is enough for the FORM/RIdx header plus the Exec chunk's
    // magic in any normal blorb. Larger if we ever hit one in the wild
    // with a massive image-resource block before Exec.
    guard let header = try handle.read(upToCount: 4096) else { return nil }
    return detect(header: header)
  }

  // MARK: - Magic constants

  private static let glulMagic: [UInt8] = [0x47, 0x6C, 0x75, 0x6C]  // "Glul"
  private static let formMagic: [UInt8] = [0x46, 0x4F, 0x52, 0x4D]  // "FORM"
  private static let ifrsMagic: [UInt8] = [0x49, 0x46, 0x52, 0x53]  // "IFRS"
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
