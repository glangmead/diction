import Testing
import Foundation
@testable import Diction

// A secondary buffer window (Blue Lacuna's bottom "Topics" panel) accumulates
// flowing styled text with the same clear/append semantics as the transcript,
// via the shared `StyledText.applyBufferContent`.

private func content(_ json: String) throws -> RemGlkUpdate.Content {
  try JSONDecoder().decode(RemGlkUpdate.Content.self, from: Data(json.utf8))
}

@Test("Buffer snapshot appends lines and merges on the append flag")
func bufferAppendsAndMerges() throws {
  var window = BufferWindowSnapshot(id: 4)
  window.apply(
    content: try content(
      #"{"id":4,"text":[{"content":[{"text":"Topics: "}]},{"content":[{"text":"this"}],"append":true}]}"#),
    styleTable: nil
  )
  #expect(window.lines.count == 1)
  #expect(window.lines[0].plainText == "Topics: this")
}

@Test("Buffer snapshot clear wipes prior lines before the redraw")
func bufferClearWipes() throws {
  var window = BufferWindowSnapshot(id: 4)
  window.apply(content: try content(#"{"id":4,"text":[{"content":[{"text":"old"}]}]}"#), styleTable: nil)
  window.apply(
    content: try content(#"{"id":4,"clear":true,"text":[{"content":[{"text":"new"}]}]}"#),
    styleTable: nil
  )
  #expect(window.lines.count == 1)
  #expect(window.lines[0].plainText == "new")
}

@Test("Buffer accumulation skips lines with no runs")
func bufferSkipsEmptyLines() throws {
  var lines: [StyledText] = []
  StyledText.applyBufferContent(
    try content(#"{"id":4,"text":[{"content":[{"text":"a"}]},{"content":[]}]}"#),
    styleTable: nil,
    into: &lines
  )
  #expect(lines.count == 1)
  #expect(lines[0].plainText == "a")
}

@Test("Buffer accumulation resolves runs against the window's style table")
func bufferResolvesStyles() throws {
  var window = BufferWindowSnapshot(id: 4)
  window.apply(
    content: try content(#"{"id":4,"text":[{"content":[{"style":"user2","text":"topic"}]}]}"#),
    styleTable: [".Style_user2": StyleAttributes(color: "#0000FF")]
  )
  #expect(window.lines[0].runs[0].attributes.color == "#0000FF")
}
