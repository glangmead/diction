import Foundation

/// A single line of interpreter output: styled runs, used for both the buffer
/// transcript and grid (status) window rows. Each run carries its resolved
/// effective styling so presentation doesn't have to walk the window's style
/// table itself.
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
    /// Effective look: the window's named-style entry overlaid with this run's
    /// own `css_styles`. Empty `StyleAttributes()` when neither applies.
    var attributes: StyleAttributes = StyleAttributes()
    /// Hyperlink target value if this run is a link (`glk_set_hyperlink`).
    var hyperlink: Int?
  }

  var plainText: String {
    runs.map(\.text).joined()
  }
}

extension StyledText {
  /// Build a styled line from RemGlk runs, resolving each run's effective look
  /// against the owning window's named-style table — the run's `css_styles`
  /// overrides the table. Pass `nil` when no table is known; per-run css still
  /// resolves over an empty base.
  init(from remGlkRuns: [RemGlkUpdate.TextRun], styleTable: [String: StyleAttributes]?) {
    self.id = UUID()
    self.runs = remGlkRuns.map { run in
      let named = run.style.flatMap { styleTable?[".Style_\($0.rawValue)"] } ?? StyleAttributes()
      return Run(
        text: run.text,
        style: run.style ?? .normal,
        attributes: named.overlaying(run.cssStyles),
        hyperlink: run.hyperlink
      )
    }
  }

  init(from remGlkRuns: [RemGlkUpdate.TextRun]) {
    self.init(from: remGlkRuns, styleTable: nil)
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
