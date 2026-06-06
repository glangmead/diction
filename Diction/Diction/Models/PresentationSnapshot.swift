import Foundation

/// A serializable freeze of an `InterpreterSession`'s renderable + protocol
/// state — the "display half" of a resume snapshot (Option S). Captured on the
/// same settled-update boundary at which the interpreter autosaves its VM, so the
/// two halves always describe the same turn. Repainting this reproduces the
/// transcript, status / secondary windows, and input affordance instantly,
/// before the interpreter has booted and restored its VM.
struct PresentationSnapshot: Equatable, Sendable, Codable {
  var transcript: [StyledText]
  /// Optional so snapshots written before input history existed still decode
  /// (synthesized decoding treats a missing key as nil). Restored as `[]`.
  var inputHistory: [String]?
  var lastResponse: [StyledText]
  var lastResponseStart: Int
  var transcriptClears: Int
  var inputMode: RemGlkUpdate.InputType?
  var currentGen: Int
  var currentWindow: Int
  var windowTypes: [Int: RemGlkUpdate.WindowType]
  var windowStyles: [Int: [String: StyleAttributes]]
  var gridSnapshots: [Int: GridWindowSnapshot]
  var primaryBufferID: Int?
  var secondaryBuffers: [Int: BufferWindowSnapshot]
}
