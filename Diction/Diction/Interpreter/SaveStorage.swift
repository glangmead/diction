import Foundation

/// Maps RemGlk fileref dialog requests (save / restore / transcript /
/// command-record / data resource) to on-disk paths inside the app's
/// Documents directory. One slot per (game, filetype) — the interpreter
/// overwrites in place rather than maintaining a slot list.
///
/// Layout:
///   <Documents>/Saves/<gameID>/save.dat
///   <Documents>/Saves/<gameID>/transcript.txt
///   <Documents>/Saves/<gameID>/command.txt
///   <Documents>/Saves/<gameID>/data.dat
///
/// Documents (not Application Support) so the user can browse and back up
/// their saves in the Files app — this requires `UIFileSharingEnabled`
/// and `LSSupportsOpeningDocumentsInPlace` in Info.plist.
nonisolated enum SaveStorage {
  /// Resolves a path for the given dialog. Returns `nil` to signal the
  /// game that the "user" cancelled (e.g. attempting to read a save slot
  /// that doesn't exist yet). The game then prints its own "Restore
  /// failed" / "Cancelled" message.
  static func resolvePath(
    gameID: String,
    filetype: RemGlkUpdate.FileType,
    mode: RemGlkUpdate.FileMode
  ) -> String? {
    guard let gameDir = gameDirectoryURL(gameID: gameID) else { return nil }
    let path = gameDir.appendingPathComponent(filename(for: filetype),
                                              isDirectory: false).path

    switch mode {
    case .read:
      return FileManager.default.fileExists(atPath: path) ? path : nil
    case .write, .readwrite, .writeappend:
      try? FileManager.default.createDirectory(
        at: gameDir,
        withIntermediateDirectories: true
      )
      return path
    }
  }

  /// A stable per-game identifier derived from the story file's name.
  /// Sanitized to keep us inside POSIX-friendly characters.
  static func gameID(for storyURL: URL) -> String {
    let stem = storyURL.deletingPathExtension().lastPathComponent
    return stem
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
  }

  private static func gameDirectoryURL(gameID: String) -> URL? {
    guard let documents = try? FileManager.default.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ) else { return nil }
    return documents
      .appendingPathComponent("Saves", isDirectory: true)
      .appendingPathComponent(gameID, isDirectory: true)
  }

  private static func filename(for type: RemGlkUpdate.FileType) -> String {
    switch type {
    case .save: "save.dat"
    case .transcript: "transcript.txt"
    case .command: "command.txt"
    case .data: "data.dat"
    }
  }
}

extension SaveStorage {
  /// Maps an emglken fileref basename to a concrete file inside the game's save
  /// directory (`<Documents>/Saves/<gameID>/<basename>`), creating the directory.
  /// Returns nil for an empty/unsafe basename. Read and write agree by
  /// construction because both derive the URL from (gameID, basename).
  static func emglkenFileURL(gameID: String, basename: String) -> URL? {
    guard !basename.isEmpty, !basename.contains("/"), basename != "..",
          !basename.contains(".."), let gameDir = gameDirectoryURL(gameID: gameID) else {
      return nil
    }
    try? FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    return gameDir.appendingPathComponent(basename, isDirectory: false)
  }
}
