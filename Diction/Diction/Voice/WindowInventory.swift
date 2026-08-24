import Foundation

/// Turns a session's live windows into the numbered slots the `windows` command
/// lists and `window N` reads aloud. Numbering is story-first — slot 1 is the
/// main story text, then grid (status) windows, then secondary buffer panels,
/// each in on-screen `top` order. Labels describe type + position relative to the
/// story; content is the rows `window N` should speak.
nonisolated enum WindowInventory {
  struct Slot: Equatable {
    /// 1-based, stable address used by `window N`.
    let number: Int
    /// Type + position, e.g. "status bar above the story, 1 row".
    let label: String
    /// Non-blank lines this window reads when addressed.
    let contentLines: [String]
  }

  static func slots(
    storyTop: Int,
    lastResponse: [StyledText],
    statusWindows: [GridWindowSnapshot],
    secondaryBuffers: [BufferWindowSnapshot]
  ) -> [Slot] {
    var slots: [Slot] = [
      Slot(number: 1, label: "main story text", contentLines: nonBlank(lastResponse))
    ]
    for grid in statusWindows {
      let rows = grid.height == 1 ? "1 row" : "\(max(grid.height, grid.lines.count)) rows"
      slots.append(Slot(
        number: slots.count + 1,
        label: "status bar \(position(of: grid.top, storyTop: storyTop)), \(rows)",
        contentLines: nonBlank(grid.lines)))
    }
    for panel in secondaryBuffers {
      slots.append(Slot(
        number: slots.count + 1,
        label: "panel \(position(of: panel.top, storyTop: storyTop))",
        contentLines: nonBlank(panel.lines)))
    }
    return slots
  }

  /// The `windows` answer: one numbered line per slot, labeled by type+position.
  static func listReadout(slots: [Slot]) -> VoiceReadout {
    VoiceReadout(
      title: "Windows",
      lines: slots.map { VoiceReadout.Line(number: $0.number, text: $0.label) })
  }

  /// A single window's contents for `window N` — its label as the title, its rows
  /// as unnumbered lines (or a note when empty).
  static func contentReadout(for slot: Slot) -> VoiceReadout {
    let lines = slot.contentLines.isEmpty
      ? [VoiceReadout.Line(number: nil, text: "Empty.")]
      : slot.contentLines.map { VoiceReadout.Line(number: nil, text: $0) }
    return VoiceReadout(title: slot.label.capitalizedFirstLetter, lines: lines)
  }

  /// Above vs below the story, from the window's `top` against the story's.
  private static func position(of top: Int, storyTop: Int) -> String {
    top < storyTop ? "above the story" : "below the story"
  }

  /// A window's non-empty lines as plain strings, for narration and the overlay.
  private static func nonBlank(_ lines: [StyledText]) -> [String] {
    lines.map { $0.plainText.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}

private nonisolated extension String {
  /// "status bar above the story" → "Status bar above the story", for a readout title.
  var capitalizedFirstLetter: String {
    guard let first else { return self }
    return first.uppercased() + dropFirst()
  }
}
