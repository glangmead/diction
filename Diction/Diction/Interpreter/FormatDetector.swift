import Foundation

nonisolated enum StoryFormat: String, Sendable {
  case zMachine
  case glulx
}

/// Identifies a story file's format from its header bytes.
/// Z-machine files start with a single version byte (1–8).
/// Glulx files start with the four-byte magic "Glul".
nonisolated enum FormatDetector {
  static func detect(header: Data) -> StoryFormat? {
    guard header.count >= 4 else { return nil }

    let version = header[0]
    if (1...8).contains(version) {
      return .zMachine
    }

    if header[0] == 0x47,
       header[1] == 0x6C,
       header[2] == 0x75,
       header[3] == 0x6C {
      return .glulx
    }

    return nil
  }

  static func detect(url: URL) throws -> StoryFormat? {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    guard let header = try handle.read(upToCount: 64) else { return nil }
    return detect(header: header)
  }
}
