import Foundation

/// Discovers and tracks story files from the app bundle and Documents.
@Observable
@MainActor
final class StoryFileManager {
  private(set) var stories: [StoryFile] = []

  private let documentsURL: URL
  private let lastPlayedKey = "lastPlayed"

  private static let bundledGames: [(name: String, ext: String, title: String)] = [
    ("devours", "z5", "All Things Devours")
  ]

  init() {
    documentsURL = FileManager.default.urls(
      for: .documentDirectory, in: .userDomainMask
    )[0]
    refresh()
  }

  func refresh() {
    var all: [StoryFile] = []
    all.append(contentsOf: bundledStories())
    all.append(contentsOf: importedStories())
    stories = all.sorted { lhs, rhs in
      (lhs.lastPlayed ?? .distantPast) > (rhs.lastPlayed ?? .distantPast)
    }
  }

  func recordPlayed(_ story: StoryFile) {
    var dates = lastPlayedMap()
    dates[story.url.lastPathComponent] = Date()
    saveLastPlayedMap(dates)
    refresh()
  }

  /// Copy an imported file into Documents. The system passes a
  /// security-scoped URL, so the caller is responsible for managing the scope.
  @discardableResult
  func importStory(from url: URL) throws -> StoryFile {
    let dest = documentsURL.appendingPathComponent(url.lastPathComponent)
    if !FileManager.default.fileExists(atPath: dest.path) {
      try FileManager.default.copyItem(at: url, to: dest)
    }
    refresh()
    return stories.first { $0.url == dest } ?? StoryFile(
      url: dest,
      title: url.deletingPathExtension().lastPathComponent,
      format: (try? FormatDetector.detect(url: dest)) ?? .zMachine,
      source: .imported,
      lastPlayed: nil
    )
  }

  /// Remove an imported or downloaded story from Documents and forget its
  /// last-played timestamp. Bundled games live in the read-only app bundle, so
  /// they can't be deleted (and the UI doesn't offer it for them).
  func deleteStory(_ story: StoryFile) throws {
    guard story.source != .bundled else { throw StoryFileError.cannotDeleteBundled }
    try FileManager.default.removeItem(at: story.url)
    var dates = lastPlayedMap()
    dates[story.url.lastPathComponent] = nil
    saveLastPlayedMap(dates)
    refresh()
  }

  // MARK: - Internals

  private func bundledStories() -> [StoryFile] {
    let dates = lastPlayedMap()
    return Self.bundledGames.compactMap { name, ext, title in
      guard let url = Bundle.main.url(
        forResource: name, withExtension: ext
      ) else { return nil }
      let format = (try? FormatDetector.detect(url: url)) ?? .zMachine
      return StoryFile(
        url: url,
        title: title,
        format: format,
        source: .bundled,
        lastPlayed: dates["\(name).\(ext)"]
      )
    }
  }

  private func importedStories() -> [StoryFile] {
    let dates = lastPlayedMap()
    let fm = FileManager.default
    guard let urls = try? fm.contentsOfDirectory(
      at: documentsURL,
      includingPropertiesForKeys: nil
    ) else { return [] }

    return urls.compactMap { url in
      guard StoryFile.supportedExtensions.contains(
        url.pathExtension.lowercased()
      ) else { return nil }
      let format = (try? FormatDetector.detect(url: url)) ?? .zMachine
      return StoryFile(
        url: url,
        title: url.deletingPathExtension().lastPathComponent,
        format: format,
        source: .imported,
        lastPlayed: dates[url.lastPathComponent]
      )
    }
  }

  private func lastPlayedMap() -> [String: Date] {
    UserDefaults.standard.object(forKey: lastPlayedKey)
      as? [String: Date] ?? [:]
  }

  private func saveLastPlayedMap(_ map: [String: Date]) {
    UserDefaults.standard.set(map, forKey: lastPlayedKey)
  }
}

nonisolated enum StoryFileError: LocalizedError {
  case cannotDeleteBundled

  var errorDescription: String? {
    switch self {
    case .cannotDeleteBundled:
      return "Bundled games can't be removed."
    }
  }
}
