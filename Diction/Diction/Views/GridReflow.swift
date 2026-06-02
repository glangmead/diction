import Foundation

/// Compacts a grid (status) window's rows so it can render in a larger font:
/// drops blank columns at the edges and collapses interior all-blank column runs
/// to two, removing the *same* columns from every row so alignment is preserved.
///
/// Gated by `maxDistinctSpecials`: if the block contains more than that many
/// distinct non-alphanumeric, non-space characters it's probably ASCII art (a
/// map, a box-drawn frame) rather than a status bar, so it's left untouched.
enum GridReflow {
  static let maxDistinctSpecials = 5

  static func reflow(_ rows: [String]) -> [String] {
    guard !rows.isEmpty else { return rows }

    // ASCII-art guard: too many distinct special characters → leave it alone.
    let specials = Set(rows.joined().filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace })
    guard specials.count <= maxDistinctSpecials else { return rows }

    let width = rows.map(\.count).max() ?? 0
    guard width > 0 else { return rows }
    // Pad ragged rows so every column index is defined.
    let grid = rows.map { row -> [Character] in
      let chars = Array(row)
      return chars.count < width
        ? chars + Array(repeating: " ", count: width - chars.count)
        : chars
    }

    func columnBlank(_ col: Int) -> Bool { grid.allSatisfy { $0[col] == " " } }
    let content = (0..<width).filter { !columnBlank($0) }
    guard let first = content.first, let last = content.last else { return rows }

    // Keep all content columns; drop the leading/trailing blank runs (outside
    // first…last); collapse each interior blank run to two columns.
    var keep: [Int] = []
    var col = first
    while col <= last {
      if !columnBlank(col) {
        keep.append(col)
        col += 1
      } else {
        var run = col
        while run <= last && columnBlank(run) { run += 1 }
        keep.append(contentsOf: col..<(col + min(run - col, 2)))
        col = run
      }
    }
    return grid.map { row in String(keep.map { row[$0] }) }
  }
}
