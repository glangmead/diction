import Foundation

/// Compacts a grid (status) window's rows so it can render in a larger font:
/// drops blank columns at the edges and collapses interior all-blank column runs
/// to two, removing the *same* columns from every row so alignment is preserved.
///
/// Edge (left/right margin) trimming always runs — it only de-margins the block.
/// The interior collapse is gated by `maxDistinctSpecials`: if the block has more
/// than that many distinct non-alphanumeric, non-space characters it's probably
/// ASCII art (a map, a box-drawn frame), so its interior spacing is preserved —
/// but it's still de-margined so it reads larger.
enum GridReflow {
  static let maxDistinctSpecials = 5

  /// The reflowed rows plus the mapping a caller needs to place a cursor over the
  /// result: which original column each displayed column shows, and how many top
  /// rows were dropped.
  struct Reflowed: Equatable, Sendable {
    var rows: [String]
    /// Displayed column `i` renders original grid column `keptColumns[i]` (sorted).
    var keptColumns: [Int]
    /// Original grid row `r` renders at displayed row `r - droppedTopRows`.
    var droppedTopRows: Int

    /// Maps an original grid cursor — glkapi's `xpos`/`ypos` — to its position in
    /// the reflowed block, or nil if it falls outside the visible rows. A cursor
    /// sitting in a trimmed/collapsed gap lands just right of the preceding text.
    func cursor(col: Int, row: Int) -> (col: Int, row: Int)? {
      let mappedRow = row - droppedTopRows
      guard mappedRow >= 0, mappedRow < rows.count else { return nil }
      let mappedCol = keptColumns.firstIndex(where: { $0 >= col }) ?? keptColumns.count
      return (mappedCol, mappedRow)
    }
  }

  static func reflow(_ input: [String]) -> Reflowed {
    guard !input.isEmpty else { return Reflowed(rows: input, keptColumns: [], droppedTopRows: 0) }

    // Drop leading/trailing all-blank ROWS (top/bottom margins). Like the side
    // margins, this never disturbs internal layout, so it's safe even for art —
    // and Bureaucracy's form has a few blank lines top and bottom that otherwise
    // eat rows of the cap. Interior blank rows are preserved.
    func blankRow(_ row: String) -> Bool { row.allSatisfy(\.isWhitespace) }
    let droppedTop = input.prefix(while: blankRow).count
    var rows = Array(input.dropFirst(droppedTop))
    while let last = rows.last, blankRow(last) { rows.removeLast() }
    guard !rows.isEmpty else { return Reflowed(rows: [], keptColumns: [], droppedTopRows: droppedTop) }

    let width = rows.map(\.count).max() ?? 0
    guard width > 0 else { return Reflowed(rows: rows, keptColumns: [], droppedTopRows: droppedTop) }
    // Pad ragged rows so every column index is defined.
    let grid = rows.map { row -> [Character] in
      let chars = Array(row)
      return chars.count < width
        ? chars + Array(repeating: " ", count: width - chars.count)
        : chars
    }

    func columnBlank(_ col: Int) -> Bool { grid.allSatisfy { $0[col] == " " } }
    let content = (0..<width).filter { !columnBlank($0) }
    guard let first = content.first, let last = content.last else {
      return Reflowed(rows: rows, keptColumns: Array(0..<width), droppedTopRows: droppedTop)
    }

    // Trimming the all-blank LEFT/RIGHT margins (the columns outside first…last) is
    // always safe — it de-margins the block without disturbing any internal
    // alignment — so we do it even for ASCII art: a wide form or map padded with
    // side margins narrows to its content and reads much larger when fit-to-width.
    // Collapsing INTERIOR blank runs, by contrast, would mangle art's internal
    // spacing, so only that is gated by the distinct-specials guard.
    let specials = Set(rows.joined().filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace })
    let collapseInterior = specials.count <= maxDistinctSpecials

    var keep: [Int] = []
    var col = first
    while col <= last {
      if !columnBlank(col) {
        keep.append(col)
        col += 1
      } else {
        var run = col
        while run <= last && columnBlank(run) { run += 1 }
        let take = collapseInterior ? min(run - col, 2) : run - col
        keep.append(contentsOf: col..<(col + take))
        col = run
      }
    }
    let outRows = grid.map { row in String(keep.map { row[$0] }) }
    return Reflowed(rows: outRows, keptColumns: keep, droppedTopRows: droppedTop)
  }
}
