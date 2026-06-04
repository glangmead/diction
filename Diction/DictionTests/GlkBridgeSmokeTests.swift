import Testing
import Foundation
@testable import Diction

private final class GlkBundleMarker {}

/// Drives the full classic-Glk bridge in a real (hosted) WKWebView: load a
/// bundled Z-machine game through `InterpreterSession`, confirm it renders the
/// opening and accepts input, then play one turn. This is the switchover oracle —
/// it fails if the vendored stack doesn't boot/play in the WebView.
@MainActor
@Test("classic-glk bridge loads a Z-machine game and plays a turn", .timeLimit(.minutes(1)))
func glkBridgeLoadsAndPlays() async throws {
  let bundle = Bundle(for: GlkBundleMarker.self)
  let url = try #require(bundle.url(forResource: "minizork", withExtension: "z3"))

  let session = InterpreterSession()
  try await session.load(url)

  #expect(!session.transcript.isEmpty)
  #expect(session.isAwaitingInput)
  let opening = session.transcript.map(\.plainText).joined()
  #expect(opening.contains("West of House"))

  let before = session.transcript.count
  await session.send("open mailbox")

  #expect(session.transcript.count > before)
  #expect(session.isAwaitingInput)
  let response = session.lastResponse.map(\.plainText).joined().lowercased()
  #expect(response.contains("leaflet") || response.contains("mailbox"))

  await session.shutdown()
}

/// The autosave feature, end-to-end in the WebView: play a move, grab the VM
/// autosave, tear down, start a fresh session restoring that snapshot, and
/// confirm the VM truly resumed — re-opening the already-opened mailbox must say
/// it's *already* open rather than revealing the leaflet again.
@MainActor
@Test("classic-glk bridge autosaves and restores VM state", .timeLimit(.minutes(1)))
func glkBridgeAutosaveRoundTrips() async throws {
  let bundle = Bundle(for: GlkBundleMarker.self)
  let url = try #require(bundle.url(forResource: "minizork", withExtension: "z3"))

  let first = InterpreterSession()
  try await first.load(url)
  await first.send("open mailbox")
  let snapshot = try #require(first.engineSnapshot)
  await first.shutdown()

  let resumed = InterpreterSession()
  try await resumed.load(url, restoring: snapshot)
  await resumed.send("open mailbox")
  let response = resumed.lastResponse.map(\.plainText).joined().lowercased()
  #expect(response.contains("already"))
  await resumed.shutdown()
}

/// The Glulx path through Quixe, in the WebView: load a Glulx story, confirm it
/// renders and accepts input, play a move, and confirm the VM autosaved.
@MainActor
@Test("classic-glk bridge loads a Glulx game via Quixe and autosaves", .timeLimit(.minutes(1)))
func glkBridgeGlulxLoadsAndAutosaves() async throws {
  let bundle = Bundle(for: GlkBundleMarker.self)
  let url = try #require(bundle.url(forResource: "glulxercise", withExtension: "ulx"))

  let session = InterpreterSession()
  try await session.load(url)

  #expect(!session.transcript.isEmpty)
  #expect(session.isAwaitingInput)
  let opening = session.transcript.map(\.plainText).joined()
  #expect(opening.contains("Glulxercise"))

  let before = session.transcript.count
  await session.send("help")
  #expect(session.transcript.count > before)
  #expect(session.engineSnapshot != nil)

  await session.shutdown()
}

/// A Blorb-wrapped Glulx game (`.gblorb`): the bridge must unwrap the Blorb to
/// the bare game image before handing it to Quixe, or load fails. Regression
/// test for the doorsday.gblorb "Failed to load story" report.
@MainActor
@Test("classic-glk bridge loads a Blorb-wrapped Glulx game", .timeLimit(.minutes(1)))
func glkBridgeGlulxBlorbLoads() async throws {
  let bundle = Bundle(for: GlkBundleMarker.self)
  let url = try #require(bundle.url(forResource: "doorsday", withExtension: "gblorb"))

  let session = InterpreterSession()
  try await session.load(url)

  #expect(!session.transcript.isEmpty)
  #expect(session.isAwaitingInput)
  #expect(session.transcript.map(\.plainText).joined().localizedCaseInsensitiveContains("door"))

  await session.shutdown()
}

/// The full resume feature through disk: a session persists per-turn to a
/// GameSnapshotStore; a fresh session pointed at the same store auto-restores on
/// load — repainting the saved transcript (presentation snapshot) and resuming
/// the VM (engine snapshot), so the prior scrollback shows and the next command
/// continues from the saved state.
@MainActor
@Test("resume persists to GameSnapshotStore and restores on reload", .timeLimit(.minutes(1)))
func glkBridgeResumesFromStore() async throws {
  let bundle = Bundle(for: GlkBundleMarker.self)
  let url = try #require(bundle.url(forResource: "minizork", withExtension: "z3"))
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("resume-\(UUID().uuidString)", isDirectory: true)
  let store = GameSnapshotStore(root: root)

  let first = InterpreterSession()
  first.snapshotStore = store
  try await first.load(url)
  await first.send("open mailbox")
  await first.shutdown()

  let resumed = InterpreterSession()
  resumed.snapshotStore = store
  try await resumed.load(url)   // auto-restores from the store

  // Display restored: the prior scrollback is repainted.
  #expect(resumed.transcript.map(\.plainText).joined().contains("West of House"))
  // VM restored: re-opening the already-opened mailbox says it's already open.
  await resumed.send("open mailbox")
  #expect(resumed.lastResponse.map(\.plainText).joined().lowercased().contains("already"))

  await resumed.shutdown()
}
