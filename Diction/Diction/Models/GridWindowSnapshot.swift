import Foundation

/// The current visible state of a grid (status) window — a fixed grid of
/// character rows, each a styled line. Rebuilt replace-by-row as the
/// interpreter rewrites rows (AMFV updates the time on row 0 every turn). The
/// buffer's prose lives in the transcript; this is the panel beside it, e.g.
/// AMFV's mode / location / time / date bar.
nonisolated struct GridWindowSnapshot: Identifiable, Sendable {
  /// RemGlk window id.
  let id: Int
  /// The window's `top` coordinate, used to order stacked panels so they
  /// appear in the game's intended vertical order.
  var top: Int = 0
  /// Character columns / rows from the window's geometry.
  var width: Int
  var height: Int
  /// One styled line per row, top to bottom; length tracks `height`.
  var lines: [StyledText]

  private static var blankRow: StyledText { StyledText(runs: []) }

  /// Grow or trim `lines` to match `height` (called when geometry arrives).
  mutating func resizeRows() {
    guard height >= 0 else { return }
    if lines.count < height {
      lines.append(contentsOf: Array(repeating: Self.blankRow, count: height - lines.count))
    } else if lines.count > height {
      lines = Array(lines.prefix(height))
    }
  }

  /// Apply a grid content update: clear every row first if `content.clear`,
  /// then replace each named row with its runs, resolved against `styleTable`.
  /// Grows `lines` if a row index exceeds the current height (defensive — the
  /// geometry update normally sizes it first).
  mutating func apply(content: RemGlkUpdate.Content, styleTable: [String: StyleAttributes]?) {
    if content.clear == true {
      lines = Array(repeating: Self.blankRow, count: max(height, 0))
    }
    for gridLine in content.lines ?? [] where gridLine.line >= 0 {
      if gridLine.line >= lines.count {
        let pad = gridLine.line - lines.count + 1
        lines.append(contentsOf: Array(repeating: Self.blankRow, count: pad))
      }
      lines[gridLine.line] = StyledText(from: gridLine.content ?? [], styleTable: styleTable)
    }
    height = max(height, lines.count)
  }
}
