import Foundation

/// Persists each game's single manual save slot — the bytes the interpreter's
/// own SAVE verb produces (a Quetzal/Glulx save image). One slot per game; a new
/// SAVE overwrites in place. This is user-visible state, distinct from
/// `GameSnapshotStore`'s internal per-move resume snapshots.
///
/// The headless WebView can't touch the filesystem, so the bridge holds the slot
/// bytes in memory: this store seeds them at load (`read`) and the bridge mirrors
/// every SAVE back here (`write`) for persistence across launches.
///
/// Layout (one file per game under `root`):
///   <root>/<gameID>/save.dat
///
/// `root` defaults to `<Documents>/Saves` so the user can browse and back up
/// saves in the Files app (needs `UIFileSharingEnabled` /
/// `LSSupportsOpeningDocumentsInPlace` in Info.plist); it's injected so tests can
/// point at a temp directory.
nonisolated struct SaveStorage {
  let root: URL

  /// The slot bytes for `gameID`, or nil if the game has never been saved.
  func read(gameID: String) -> Data? {
    try? Data(contentsOf: saveURL(gameID: gameID))
  }

  /// Overwrite the single slot for `gameID`, creating the game's directory.
  /// Atomic so an interrupted write can't leave a half-written, corrupt save.
  func write(gameID: String, data: Data) {
    let url = saveURL(gameID: gameID)
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }

  /// Whether `gameID` has a save slot on disk.
  func exists(gameID: String) -> Bool {
    FileManager.default.fileExists(atPath: saveURL(gameID: gameID).path)
  }

  /// Remove `gameID`'s save slot.
  func delete(gameID: String) {
    try? FileManager.default.removeItem(at: saveURL(gameID: gameID))
  }

  private func saveURL(gameID: String) -> URL {
    root.appendingPathComponent(gameID, isDirectory: true)
      .appendingPathComponent("save.dat", isDirectory: false)
  }

  /// A stable per-game identifier derived from the story file's name, sanitized
  /// to POSIX-friendly characters.
  static func gameID(for storyURL: URL) -> String {
    storyURL.deletingPathExtension().lastPathComponent
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
  }
}

extension SaveStorage {
  /// The app's manual-save store, rooted at `<Documents>/Saves` — user-visible,
  /// distinct from `GameSnapshotStore`'s internal resume snapshots.
  static var `default`: SaveStorage {
    let documents = (try? FileManager.default.url(
      for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
      ?? FileManager.default.temporaryDirectory
    return SaveStorage(root: documents.appendingPathComponent("Saves", isDirectory: true))
  }
}
