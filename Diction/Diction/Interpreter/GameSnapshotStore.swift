import Foundation

/// A captured, resumable game state: the interpreter's own VM autosave bytes
/// paired with the Swift-side presentation snapshot. The two are persisted and
/// restored as a unit so the visible transcript and the live VM never describe
/// different turns.
struct GameSnapshot: Equatable, Sendable {
  let engine: Data
  let presentation: Data
}

/// Per-game autosnapshot store, keyed by `gameID` and validated against a story
/// signature. This is internal resume state in Application Support — distinct
/// from `SaveStorage`'s user-visible manual saves in Documents.
///
/// Layout (one directory per game under `root`):
///   <root>/<gameID>/engine.bin
///   <root>/<gameID>/presentation.json
///   <root>/<gameID>/signature.txt
///
/// `root` is injected so tests can point at a temp directory.
struct GameSnapshotStore {
  let root: URL

  /// Test seam: invoked after the new snapshot is fully staged but before it is
  /// atomically promoted. Durability tests set it to throw, simulating a crash
  /// mid-write. nil in production.
  var faultBeforePromote: (() throws -> Void)?

  private func gameDirectory(_ gameID: String) -> URL {
    root.appendingPathComponent(gameID, isDirectory: true)
  }

  /// Persist the artifact pair for `gameID` under the given `signature`. The new
  /// snapshot is written to a staging directory and then swapped into place by
  /// rename, so the committed snapshot is only ever replaced by a complete one —
  /// an interrupted write leaves the previous snapshot intact.
  func write(gameID: String, signature: String, snapshot: GameSnapshot) throws {
    let fileManager = FileManager.default
    let final = gameDirectory(gameID)
    let staging = root.appendingPathComponent("\(gameID).staging", isDirectory: true)

    try? fileManager.removeItem(at: staging)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    try snapshot.engine.write(to: staging.appendingPathComponent("engine.bin"))
    try snapshot.presentation.write(to: staging.appendingPathComponent("presentation.json"))
    try Data(signature.utf8).write(to: staging.appendingPathComponent("signature.txt"))

    try faultBeforePromote?()

    guard fileManager.fileExists(atPath: final.path) else {
      try fileManager.moveItem(at: staging, to: final)
      return
    }
    // Move the old aside, swing the new in, drop the old. On a failed swing,
    // restore the old so we never lose the previous snapshot.
    let backup = root.appendingPathComponent("\(gameID).old", isDirectory: true)
    try? fileManager.removeItem(at: backup)
    try fileManager.moveItem(at: final, to: backup)
    do {
      try fileManager.moveItem(at: staging, to: final)
      try? fileManager.removeItem(at: backup)
    } catch {
      try? fileManager.moveItem(at: backup, to: final)
      throw error
    }
  }

  /// Return the stored pair iff both artifacts are present and the stored
  /// signature matches `signature`; otherwise nil (caller starts fresh).
  func read(gameID: String, signature: String) -> GameSnapshot? {
    let dir = gameDirectory(gameID)
    guard let storedSignature = try? Data(contentsOf: dir.appendingPathComponent("signature.txt")),
          String(bytes: storedSignature, encoding: .utf8) == signature,
          let engine = try? Data(contentsOf: dir.appendingPathComponent("engine.bin")),
          let presentation = try? Data(contentsOf: dir.appendingPathComponent("presentation.json"))
    else { return nil }
    return GameSnapshot(engine: engine, presentation: presentation)
  }

  /// Remove all stored state for `gameID`.
  func delete(gameID: String) {
    try? FileManager.default.removeItem(at: gameDirectory(gameID))
  }
}

extension GameSnapshotStore {
  /// The app's resume-snapshot store, rooted in Application Support — internal
  /// resume state, distinct from the user-visible manual saves in Documents.
  static var `default`: GameSnapshotStore {
    let base = (try? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
      ?? FileManager.default.temporaryDirectory
    return GameSnapshotStore(root: base.appendingPathComponent("Snapshots", isDirectory: true))
  }
}
