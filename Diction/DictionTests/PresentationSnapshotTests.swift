import Testing
import Foundation
@testable import Diction

private func update(_ json: String) throws -> RemGlkUpdate {
  try JSONDecoder().decode(RemGlkUpdate.self, from: Data(json.utf8))
}

/// A buffer ("West of House", reverse-video over a named style) plus a one-row
/// grid ("Score: 10") with a pending line-input request — exercises transcript,
/// status window, a populated style table, and a per-run css override in one
/// shot, so the Codable round-trip actually touches `StyleAttributes`.
private let sampleUpdate = #"""
{"type":"update","gen":3,\#
"windows":[{"id":1,"type":"buffer","styles":{".Style_normal":{"color":"#000000"}}},\#
{"id":2,"type":"grid","gridwidth":20,"gridheight":1,"top":0}],\#
"content":[{"id":1,"text":[{"content":[{"style":"normal","text":"West of House","css_styles":{"reverse":1}}]}]},\#
{"id":2,"lines":[{"line":0,"content":[{"text":"Score: 10"}]}]}],\#
"input":[{"id":1,"gen":3,"type":"line"}]}
"""#

@MainActor
@Test("capture then restore into a fresh session reproduces the visible state")
func presentationSnapshotRestores() throws {
  let session = InterpreterSession()
  session.apply(try update(sampleUpdate))
  let snapshot = session.captureSnapshot()

  let restored = InterpreterSession()
  restored.restore(snapshot)

  #expect(restored.transcript == session.transcript)
  #expect(restored.statusWindows == session.statusWindows)
  #expect(restored.secondaryBufferWindows == session.secondaryBufferWindows)
  #expect(restored.isAwaitingInput == session.isAwaitingInput)
  #expect(restored.lastResponseStart == session.lastResponseStart)
}

@MainActor
@Test("a captured snapshot survives a Codable round-trip without loss")
func presentationSnapshotCodableRoundTrips() throws {
  let session = InterpreterSession()
  session.apply(try update(sampleUpdate))
  let snapshot = session.captureSnapshot()

  let data = try JSONEncoder().encode(snapshot)
  let decoded = try JSONDecoder().decode(PresentationSnapshot.self, from: data)

  #expect(decoded == snapshot)
}
