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
  /// Z-machine range is what ZVM runs (v3/4/5/8 — not the ancient v1/v2 or the
  /// graphical v6/v7); the rest are raw Glulx (`ulx`) and Blorb containers. A
  /// file whose extension passes but whose actual version isn't supported is
  /// caught at load time (`FormatDetector.zMachineVersion`).
  static let supportedExtensions: Set<String> = [
    "z3", "z4", "z5", "z8",
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
