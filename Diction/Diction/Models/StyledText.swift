import Foundation

/// A single line of interpreter output: styled runs, used for both the buffer
/// transcript and grid (status) window rows. Each run carries its resolved
/// effective styling so presentation doesn't have to walk the window's style
/// table itself.
nonisolated struct StyledText: Identifiable, Sendable, Equatable, Codable {
  let id: UUID
  var runs: [Run]

  init(id: UUID = UUID(), runs: [Run]) {
    self.id = id
    self.runs = runs
  }

  struct Run: Sendable, Equatable, Codable {
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
  nonisolated init(from remGlkRuns: [RemGlkUpdate.TextRun], styleTable: [String: StyleAttributes]?) {
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

  nonisolated init(from remGlkRuns: [RemGlkUpdate.TextRun]) {
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
  nonisolated var isUserInput: Bool {
    runs.allSatisfy { $0.style == .input }
  }

  /// Apply a buffer window's content update to a line array: a `clear` wipes it
  /// (a RESTORE/RESTART redraw for the transcript, a window redraw for a
  /// secondary panel), then each line is appended — or merged onto the previous
  /// line when its `append` flag is set. Shared by the transcript and secondary
  /// buffer windows so the accumulation can't drift between the two.
  nonisolated static func applyBufferContent(
    _ content: RemGlkUpdate.Content,
    styleTable: [String: StyleAttributes]?,
    into lines: inout [StyledText]
  ) {
    if content.clear == true { lines.removeAll() }
    guard let text = content.text else { return }
    for line in text {
      guard let runs = line.content, !runs.isEmpty else { continue }
      let entry = StyledText(from: runs, styleTable: styleTable)
      if line.append == true, var last = lines.last {
        last.runs.append(contentsOf: entry.runs)
        lines[lines.count - 1] = last
      } else {
        lines.append(entry)
      }
    }
  }
}
