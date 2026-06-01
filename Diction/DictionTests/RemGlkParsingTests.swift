import Testing
import Foundation
@testable import Diction

// Shapes here are trimmed from real captures: AMFV (bocfel) for the multi-row
// reverse-video status bar and per-run `css_styles`, Blue Lacuna (glulxe) for
// named-style colour in the window style table.

@Test("Parses AMFV's grid status bar: geometry, style table, and per-run css_styles")
func parsesAMFVStatusBar() throws {
  let json = Data("""
  {
    "type": "update", "gen": 2,
    "windows": [
      {"id": 3, "type": "grid", "rock": 2, "left": 0, "top": 0, "width": 80, "height": 7,
       "gridwidth": 80, "gridheight": 7,
       "styles": {
         ".Style_subheader": {"font-style": "normal", "font-weight": "bold", "monospace": 0},
         ".Style_user1": {"font-weight": "bold", "monospace": 1, "font-style": "normal"}
       }},
      {"id": 2, "type": "buffer", "rock": 1, "left": 0, "top": 7, "width": 80, "height": 43}
    ],
    "content": [
      {"id": 3, "clear": true, "lines": [
        {"line": 0, "content": [
          {"style": "normal", "text": "Mode:  "},
          {"style": "normal", "text": "Communications Mode", "css_styles": {"reverse": 1}}
        ]}
      ]}
    ],
    "input": [{"id": 2, "type": "line", "gen": 2}]
  }
  """.utf8)

  let update = try JSONDecoder().decode(RemGlkUpdate.self, from: json)

  let grid = try #require(update.windows?.first { $0.type == .grid })
  #expect(grid.gridheight == 7)
  #expect(grid.gridwidth == 80)
  #expect(grid.top == 0)
  #expect(grid.styles?[".Style_subheader"]?.fontWeight == "bold")
  #expect(grid.styles?[".Style_subheader"]?.monospace == false)   // JSON 0 → false
  #expect(grid.styles?[".Style_user1"]?.monospace == true)        // JSON 1 → true

  let buffer = try #require(update.windows?.first { $0.type == .buffer })
  #expect(buffer.top == 7)

  let gridContent = try #require(update.content?.first { $0.id == 3 })
  #expect(gridContent.clear == true)
  let row = try #require(gridContent.lines?.first)
  #expect(row.line == 0)
  let runs = try #require(row.content)
  #expect(runs.count == 2)
  #expect(runs[0].cssStyles == nil)                               // plain padding
  #expect(runs[1].text == "Communications Mode")
  #expect(runs[1].cssStyles?.reverse == true)                     // the second channel
}

@Test("Parses named-style colour from a window style table (Blue Lacuna shape)")
func parsesNamedStyleColour() throws {
  let json = Data("""
  {
    "type": "update",
    "windows": [
      {"id": 1, "type": "buffer", "styles": {
        ".Style_user2": {"color": "#0000FF", "font-weight": "bold", "monospace": 0, "font-size": "1em"}
      }}
    ]
  }
  """.utf8)

  let update = try JSONDecoder().decode(RemGlkUpdate.self, from: json)
  let user2 = try #require(update.windows?.first?.styles?[".Style_user2"])
  #expect(user2.color == "#0000FF")
  #expect(user2.fontWeight == "bold")
  #expect(user2.fontSize == "1em")
  #expect(user2.monospace == false)
}

@Test("StyleAttributes ignores unknown keys and round-trips reverse/monospace as 0/1")
func styleAttributesRoundTrip() throws {
  let json = Data(#"{"reverse": 1, "monospace": 0, "unknown-future-key": "ignored"}"#.utf8)
  let attrs = try JSONDecoder().decode(StyleAttributes.self, from: json)
  #expect(attrs.reverse == true)
  #expect(attrs.monospace == false)

  let reencoded = try JSONEncoder().encode(StyleAttributes(reverse: true, monospace: false))
  let object = try JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
  #expect(object?["reverse"] as? Int == 1)
  #expect(object?["monospace"] as? Int == 0)
}
