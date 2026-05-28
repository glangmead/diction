import Foundation

/// A single output entry from the interpreter, paired with optional styling
/// to drive rendering and speech synthesis prosody.
nonisolated struct StyledText: Identifiable, Sendable {
  let id: UUID
  var runs: [Run]

  init(id: UUID = UUID(), runs: [Run]) {
    self.id = id
    self.runs = runs
  }

  struct Run: Sendable {
    var text: String
    var style: RemGlkUpdate.TextStyle
  }

  var plainText: String {
    runs.map(\.text).joined()
  }
}

extension StyledText {
  init(from remGlkRuns: [RemGlkUpdate.TextRun]) {
    self.id = UUID()
    self.runs = remGlkRuns.map { run in
      Run(text: run.text, style: run.style ?? .normal)
    }
  }

  /// A "user typed this" entry, displayed inline in the transcript.
  static func userInput(_ command: String) -> StyledText {
    StyledText(runs: [
      Run(text: "> \(command)\n", style: .input)
    ])
  }

  /// True for entries created via `userInput(_:)`. Used by views that want
  /// to slice the transcript into "command + response" chunks.
  var isUserInput: Bool {
    runs.allSatisfy { $0.style == .input }
  }
}
