import Foundation

nonisolated struct StoryFile: Identifiable, Hashable, Sendable {
  var id: URL { url }
  var url: URL
  var title: String
  var format: StoryFormat
  var source: Source
  var lastPlayed: Date?

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
