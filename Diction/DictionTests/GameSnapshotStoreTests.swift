import Testing
import Foundation
@testable import Diction

/// A fresh, unique temp directory root for each test so the on-disk state is
/// hermetic and never collides with App Support or another test.
private func makeTempRoot() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("snapshot-tests-\(UUID().uuidString)", isDirectory: true)
}

@Test("write then read round-trips the snapshot for a matching signature")
func snapshotRoundTrips() throws {
  let store = GameSnapshotStore(root: makeTempRoot())
  let snap = GameSnapshot(engine: Data("vm-state".utf8), presentation: Data("transcript".utf8))
  try store.write(gameID: "curses", signature: "rel1/870601", snapshot: snap)
  #expect(store.read(gameID: "curses", signature: "rel1/870601") == snap)
}

@Test("read returns nil when the stored signature does not match")
func snapshotRejectsSignatureMismatch() throws {
  let store = GameSnapshotStore(root: makeTempRoot())
  let snap = GameSnapshot(engine: Data("vm".utf8), presentation: Data("ui".utf8))
  try store.write(gameID: "curses", signature: "rel1/870601", snapshot: snap)
  #expect(store.read(gameID: "curses", signature: "rel2/999999") == nil)
}

@Test("delete removes the stored snapshot")
func snapshotDelete() throws {
  let store = GameSnapshotStore(root: makeTempRoot())
  let snap = GameSnapshot(engine: Data("vm".utf8), presentation: Data("ui".utf8))
  try store.write(gameID: "curses", signature: "rel1/870601", snapshot: snap)
  store.delete(gameID: "curses")
  #expect(store.read(gameID: "curses", signature: "rel1/870601") == nil)
}

@Test("an interrupted write leaves the previously committed snapshot intact")
func snapshotWriteIsAtomic() throws {
  var store = GameSnapshotStore(root: makeTempRoot())
  let original = GameSnapshot(engine: Data("A-vm".utf8), presentation: Data("A-ui".utf8))
  try store.write(gameID: "curses", signature: "rel1/870601", snapshot: original)

  // Simulate a crash after staging the new snapshot but before committing it.
  store.faultBeforePromote = { throw CocoaError(.fileWriteUnknown) }
  let replacement = GameSnapshot(engine: Data("B-vm".utf8), presentation: Data("B-ui".utf8))
  #expect(throws: (any Error).self) {
    try store.write(gameID: "curses", signature: "rel1/870601", snapshot: replacement)
  }
  // The original survives the failed write.
  #expect(store.read(gameID: "curses", signature: "rel1/870601") == original)
}

@Test("read returns nil when one artifact is missing (all-or-nothing)")
func snapshotAllOrNothing() throws {
  let root = makeTempRoot()
  let store = GameSnapshotStore(root: root)
  let snap = GameSnapshot(engine: Data("vm".utf8), presentation: Data("ui".utf8))
  try store.write(gameID: "curses", signature: "rel1/870601", snapshot: snap)
  // Lose just the engine half; the pair must no longer restore.
  try FileManager.default.removeItem(
    at: root.appendingPathComponent("curses/engine.bin"))
  #expect(store.read(gameID: "curses", signature: "rel1/870601") == nil)
}
