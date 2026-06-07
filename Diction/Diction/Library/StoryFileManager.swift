import CryptoKit
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

  /// Copy an imported file into Documents under a collision-free name. The system
  /// passes a security-scoped URL, so the caller is responsible for managing the
  /// scope. This is the no-confirmation path (system open-in); the interactive Add
  /// button routes through `contentDuplicate` + `addStory` so it can prompt first.
  @discardableResult
  func importStory(from url: URL) throws -> StoryFile {
    try addStory(from: url, preferredName: nil)
  }

  /// The library file byte-identical to the one at `url`, if any. Hashes the
  /// candidate and every current library file on demand (story files are tiny);
  /// name is irrelevant — only the bytes are compared.
  func contentDuplicate(of url: URL) -> StoryFile? {
    guard let incoming = Self.sha256(ofFileAt: url) else { return nil }
    return stories.first { Self.sha256(ofFileAt: $0.url) == incoming }
  }

  /// Copy the file at `url` into Documents under a unique name and return the
  /// resulting `StoryFile`. `preferredName` (e.g. an IFDB title) overrides the
  /// source filename; a name collision in Documents is resolved with a macOS-style
  /// ` (2)` suffix. No content check here — callers decide whether to prompt first.
  @discardableResult
  func addStory(from url: URL, preferredName: String?) throws -> StoryFile {
    let base = preferredName ?? url.lastPathComponent
    let name = Self.uniqueFilename(base: base, existing: existingDocumentFilenames())
    let dest = documentsURL.appendingPathComponent(name)
    try FileManager.default.copyItem(at: url, to: dest)
    refresh()
    return stories.first { $0.url == dest } ?? StoryFile(
      url: dest,
      title: dest.deletingPathExtension().lastPathComponent,
      format: (try? FormatDetector.detect(url: dest)) ?? .zMachine,
      source: .imported,
      lastPlayed: nil
    )
  }

  private func existingDocumentFilenames() -> Set<String> {
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: documentsURL, includingPropertiesForKeys: nil
    ) else { return [] }
    return Set(urls.map { $0.lastPathComponent })
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

  // MARK: - Hashing & naming

  /// Hex SHA-256 of `data`. Used to detect byte-identical games regardless of name.
  nonisolated static func sha256(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// Hex SHA-256 of the file at `url`, or nil if it can't be read. Story files are
  /// small (well under a megabyte), so reading them whole is cheap.
  nonisolated static func sha256(ofFileAt url: URL) -> String? {
    (try? Data(contentsOf: url)).map(sha256)
  }

  /// macOS-style collision-free filename: if `base` is taken, suffix the stem with
  /// ` (2)`, ` (3)`, … while preserving the extension (`amfv.z5` → `amfv (2).z5`).
  nonisolated static func uniqueFilename(base: String, existing: Set<String>) -> String {
    guard existing.contains(base) else { return base }
    let url = URL(fileURLWithPath: base)
    let ext = url.pathExtension
    let stem = url.deletingPathExtension().lastPathComponent
    var index = 2
    while true {
      let candidate = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
      if !existing.contains(candidate) { return candidate }
      index += 1
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
