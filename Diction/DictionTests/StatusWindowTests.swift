import Testing
import Foundation
@testable import Diction

// The session resolves each run's effective look from two channels — the
// window's named-style table and the run's own `css_styles` — and maintains
// grid (status) windows as replace-by-row snapshots. These cover the pure
// pieces that `InterpreterSession.apply` orchestrates.

@Test("css override wins over the named style; unset fields fall through")
func cssOverrideWins() {
  let named = StyleAttributes(color: "#111111", reverse: false)
  let merged = named.overlaying(StyleAttributes(color: "#FFFFFF"))
  #expect(merged.color == "#FFFFFF")   // override
  #expect(merged.reverse == false)     // kept from the named style
}

@Test("Run styling resolves window table for named styles and css for per-run")
func resolvesEffectiveStyle() {
  let table = [".Style_user2": StyleAttributes(color: "#0000FF", fontWeight: "bold")]
  let runs = [
    RemGlkUpdate.TextRun(style: .user2, text: "thin man"),
    RemGlkUpdate.TextRun(style: .normal, text: "bar", cssStyles: StyleAttributes(reverse: true))
  ]
  let line = StyledText(from: runs, styleTable: table)
  #expect(line.runs[0].attributes.color == "#0000FF")    // from the named table
  #expect(line.runs[0].attributes.fontWeight == "bold")
  #expect(line.runs[1].attributes.reverse == true)        // from the per-run css
  #expect(line.runs[1].attributes.color == nil)
}

@Test("Grid snapshot builds AMFV's status row with resolved reverse styling")
func gridSnapshotFromAMFVUpdate() throws {
  let json = Data("""
  {"type": "update",
   "windows": [{"id": 3, "type": "grid", "gridwidth": 80, "gridheight": 2, "styles": {}}],
   "content": [{"id": 3, "clear": true, "lines": [
     {"line": 0, "content": [
       {"style": "normal", "text": "Mode:  "},
       {"style": "normal", "text": "Communications Mode", "css_styles": {"reverse": 1}}
     ]}
   ]}]}
  """.utf8)
  let update = try JSONDecoder().decode(RemGlkUpdate.self, from: json)
  let window = try #require(update.windows?.first)

  var grid = GridWindowSnapshot(
    id: window.id, width: window.gridwidth ?? 0, height: window.gridheight ?? 0, lines: []
  )
  grid.resizeRows()
  #expect(grid.lines.count == 2)

  let content = try #require(update.content?.first)
  grid.apply(content: content, styleTable: window.styles)
  #expect(grid.lines[0].plainText == "Mode:  Communications Mode")
  #expect(grid.lines[0].runs.last?.attributes.reverse == true)
  #expect(grid.lines[1].plainText == "")   // untouched row stays blank
}

@Test("Grid snapshot replaces a single row in place, leaving others intact")
func gridSnapshotReplaceByLine() throws {
  func content(_ json: String) throws -> RemGlkUpdate.Content {
    try JSONDecoder().decode(RemGlkUpdate.Content.self, from: Data(json.utf8))
  }

  var grid = GridWindowSnapshot(id: 3, width: 10, height: 3, lines: [])
  grid.resizeRows()

  try grid.apply(
    content: content(#"{"id": 3, "lines": [{"line": 1, "content": [{"text": "ROW ONE"}]}]}"#),
    styleTable: nil
  )
  #expect(grid.lines[1].plainText == "ROW ONE")

  try grid.apply(
    content: content(#"{"id": 3, "lines": [{"line": 2, "content": [{"text": "ROW TWO"}]}]}"#),
    styleTable: nil
  )
  #expect(grid.lines[1].plainText == "ROW ONE")   // row 1 untouched
  #expect(grid.lines[2].plainText == "ROW TWO")
}
