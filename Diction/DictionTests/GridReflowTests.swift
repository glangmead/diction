import Testing
@testable import Diction

// GridReflow compacts status-window rows (drop edge blank columns, collapse
// interior all-blank runs to two) while preserving column alignment, so the bar
// can render larger. ASCII-art-ish blocks (many distinct specials) keep their
// interior spacing but are still de-margined (edge blanks trimmed). It also
// returns the column/row mapping a caller needs to place a cursor over the result.

@Suite("Grid reflow")
struct GridReflowTests {
  @Test("Trims blank columns at the edges")
  func trimsEdges() {
    #expect(GridReflow.reflow(["  ab  ", "  cd  "]).rows == ["ab", "cd"])
  }

  @Test("Collapses an interior all-blank column run to two")
  func collapsesInterior() {
    #expect(GridReflow.reflow(["a     b", "c     d"]).rows == ["a  b", "c  d"])
  }

  @Test("Keeps columns that aren't blank in every row; alignment preserved")
  func keepsPartialBlanks() {
    // The 5-blank run (cols 2–6, blank in both) collapses to 2; edges trimmed.
    #expect(GridReflow.reflow(["ab     cd", "ef     gh"]).rows == ["ab  cd", "ef  gh"])
  }

  @Test("Single-row bar trims ends and collapses the middle gap")
  func singleRow() {
    #expect(GridReflow.reflow(["  hi   there  "]).rows == ["hi  there"])
  }

  @Test("Trims leading and trailing blank rows, keeps interior blank rows")
  func trimsBlankRows() {
    // Two blank rows lead, two trail; the interior blank row stays (padded to width).
    #expect(GridReflow.reflow(["", "  ", "ab", "", "cd", "   ", ""]).rows == ["ab", "  ", "cd"])
  }

  @Test("ASCII art (more than 5 distinct specials) keeps its interior spacing")
  func asciiArtInteriorPreserved() {
    // 10 distinct specials ⇒ art; the interior 3-blank run is kept, not collapsed.
    let art = ["+--+   <#>", "|==|   [/]"]
    #expect(GridReflow.reflow(art).rows == art)   // no margins here, so unchanged
  }

  @Test("ASCII art is still de-margined (edge blanks trimmed), interior preserved")
  func asciiArtDeMargined() {
    // Same art with 2-col side margins: edges trimmed, the 3-blank gap preserved.
    let art = ["  +--+   <#>  ", "  |==|   [/]  "]
    #expect(GridReflow.reflow(art).rows == ["+--+   <#>", "|==|   [/]"])
  }

  @Test("A bar with few distinct specials still reflows")
  func fewSpecialsReflows() {
    let input = ["Time: 1:00     Date: 5/6"]   // specials ':' '/' = 2 distinct
    let out = GridReflow.reflow(input)
    #expect(out.rows[0].count < input[0].count)     // the 5-space gap collapsed
  }

  @Test("Cursor maps through dropped top rows and trimmed left margin")
  func cursorMapsThroughTrim() {
    // 2 blank rows on top, a 2-col left margin on each content row. The original
    // cursor at (col 6, row 2) — just after "Last:" — maps to displayed (col 4,
    // row 0): two top rows dropped, two left columns trimmed.
    let out = GridReflow.reflow(["", "", "  Last:", "  Name:"])
    #expect(out.rows == ["Last:", "Name:"])
    let first = out.cursor(col: 6, row: 2)
    #expect(first?.col == 4 && first?.row == 0)
    let second = out.cursor(col: 7, row: 3)             // end of "Name:" on row 3
    #expect(second?.col == 5 && second?.row == 1)
    #expect(out.cursor(col: 0, row: 0) == nil)          // a dropped top row
  }
}
