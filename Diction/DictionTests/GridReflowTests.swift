import Testing
@testable import Diction

// GridReflow compacts status-window rows (drop edge blank columns, collapse
// interior all-blank runs to two) while preserving column alignment, so the bar
// can render larger. ASCII-art-ish blocks (many distinct specials) are skipped.

@Suite("Grid reflow")
struct GridReflowTests {
  @Test("Trims blank columns at the edges")
  func trimsEdges() {
    #expect(GridReflow.reflow(["  ab  ", "  cd  "]) == ["ab", "cd"])
  }

  @Test("Collapses an interior all-blank column run to two")
  func collapsesInterior() {
    #expect(GridReflow.reflow(["a     b", "c     d"]) == ["a  b", "c  d"])
  }

  @Test("Keeps columns that aren't blank in every row; alignment preserved")
  func keepsPartialBlanks() {
    // The 5-blank run (cols 2–6, blank in both) collapses to 2; edges trimmed.
    #expect(GridReflow.reflow(["ab     cd", "ef     gh"]) == ["ab  cd", "ef  gh"])
  }

  @Test("Single-row bar trims ends and collapses the middle gap")
  func singleRow() {
    #expect(GridReflow.reflow(["  hi   there  "]) == ["hi  there"])
  }

  @Test("Leaves likely ASCII art (more than 5 distinct specials) untouched")
  func asciiArtGuard() {
    let art = ["+--|==~", "<>[]{}/"]
    #expect(GridReflow.reflow(art) == art)
  }

  @Test("A bar with few distinct specials still reflows")
  func fewSpecialsReflows() {
    let input = ["Time: 1:00     Date: 5/6"]   // specials ':' '/' = 2 distinct
    let out = GridReflow.reflow(input)
    #expect(out[0].count < input[0].count)     // the 5-space gap collapsed
  }
}
