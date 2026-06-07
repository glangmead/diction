import Foundation

nonisolated struct StoryFile: Identifiable, Hashable, Sendable {
  var id: URL { url }
  var url: URL
  var title: String
  var format: StoryFormat
  var source: Source
  var lastPlayed: Date?
  /// Extracted/looked-up presentation metadata (cover, official title, version, …),
  /// or nil for games added before this existed and for the bundled game. Identity
  /// (`==`/`hash`) ignores it — it's presentation, not identity.
  var metadata: StoryMetadata?

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

// MARK: - Search

extension StoryFile {
  /// Case-insensitive search across every visible field. Each whitespace-separated
  /// token of `query` must appear somewhere in the combined text (token-AND), so
  /// "jota lost" matches "Lost Pig" by "Admiral Jota". An empty query matches all.
  func matches(_ query: String) -> Bool {
    let tokens = query.lowercased().split(whereSeparator: \.isWhitespace)
    guard !tokens.isEmpty else { return true }
    let haystack = searchableText
    return tokens.allSatisfy { haystack.contains($0) }
  }

  /// Every field a search should cover, lowercased and joined: the filename title,
  /// the catalog fields (official title/author/year/headline/version), and the
  /// format and source chips shown in the row.
  private var searchableText: String {
    var parts = [title, format == .zMachine ? "Z-machine" : "Glulx", source.label]
    if let metadata {
      parts.append(contentsOf: [
        metadata.title, metadata.author, metadata.year,
        metadata.headline, metadata.versionLabel
      ].compactMap { $0 })
    }
    return parts.joined(separator: " ").lowercased()
  }
}
