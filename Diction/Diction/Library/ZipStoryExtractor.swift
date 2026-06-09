import Foundation

/// Picks and extracts the playable story file from a downloaded game ZIP. Selection
/// is by file extension (the real runtime format is re-confirmed from header bytes
/// downstream by `FormatDetector`), preferring the largest match when an archive
/// bundles several files. Used by `IFDBClient.downloadGame` for zipped IFDB links.
enum ZipStoryExtractor {
  /// Extensions for Z-machine / Glulx story files, bare or Blorb-wrapped.
  static let storyExtensions: Set<String> = [
    "z1", "z2", "z3", "z4", "z5", "z6", "z7", "z8",
    "zblorb", "zlb", "gblorb", "ulx", "blb", "blorb"
  ]

  struct ExtractedStory: Equatable {
    let name: String
    let data: Data
  }

  enum ExtractError: Error { case noStoryFile }

  /// Find the story file inside `zipData` and return its name and bytes.
  static func storyFile(in zipData: Data) throws -> ExtractedStory {
    let bytes = [UInt8](zipData)
    let entries = try ZipArchive.entries(in: bytes)
    let candidates = entries.filter {
      storyExtensions.contains(($0.name as NSString).pathExtension.lowercased())
    }
    // A game zip usually holds one story file; when it bundles extras (a demo plus the
    // full game), the real game is the larger file.
    guard let entry = candidates.max(by: { $0.uncompressedSize < $1.uncompressedSize }) else {
      throw ExtractError.noStoryFile
    }
    return ExtractedStory(
      name: (entry.name as NSString).lastPathComponent,
      data: try ZipArchive.extract(entry, from: bytes))
  }
}
