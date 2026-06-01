import Foundation

nonisolated struct StoryFile: Identifiable, Hashable, Sendable {
  var id: URL { url }
  var url: URL
  var title: String
  var format: StoryFormat
  var source: Source
  var lastPlayed: Date?

  /// File extensions the app can play — the single source of truth shared by
  /// the import picker's filter (`LibraryView`) and library discovery
  /// (`StoryFileManager`), so the two can't drift (they have, twice). The
  /// Z-machine range mirrors `FormatDetector`, which accepts version bytes 1–8;
  /// the rest are raw Glulx (`ulx`) and Blorb containers.
  static let supportedExtensions: Set<String> = [
    "z1", "z2", "z3", "z4", "z5", "z6", "z7", "z8",
    "zblorb", "ulx", "gblorb", "blb", "blorb"
  ]

  static func == (lhs: StoryFile, rhs: StoryFile) -> Bool {
    lhs.url == rhs.url
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(url)
  }

  enum Source: String, Sendable, Hashable {
    case bundled
    case imported
    case downloaded

    var label: String {
      switch self {
      case .bundled: "Bundled"
      case .imported: "Imported"
      case .downloaded: "Downloaded"
      }
    }
  }
}
