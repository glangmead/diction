import Testing
import Foundation
@testable import Diction

/// `WindowInventory` turns a session's windows into the numbered slots the
/// `windows` command lists and `window N` reads. Numbering is story-first; labels
/// are type + position relative to the story's `top`.
@Suite("Window inventory")
struct WindowInventoryTests {
  private func line(_ text: String) -> StyledText {
    StyledText(runs: [.init(text: text, style: .normal)])
  }

  private func grid(id: Int, top: Int, rows: [String]) -> GridWindowSnapshot {
    GridWindowSnapshot(id: id, top: top, width: 20, height: rows.count, lines: rows.map(line))
  }

  private func secondary(id: Int, top: Int, text: String) throws -> BufferWindowSnapshot {
    var window = BufferWindowSnapshot(id: id)
    window.top = top
    window.apply(
      content: try JSONDecoder().decode(
        RemGlkUpdate.Content.self,
        from: Data(#"{"id":\#(id),"text":[{"content":[{"text":"\#(text)"}]}]}"#.utf8)),
      styleTable: nil)
    return window
  }

  @Test("slots are story-first, contiguous, and labeled by type and position")
  func slotsLayout() throws {
    let slots = WindowInventory.slots(
      storyTop: 1,
      lastResponse: [line("You are in a field.")],
      statusWindows: [grid(id: 2, top: 0, rows: ["Score: 10"])],
      secondaryBuffers: [try secondary(id: 4, top: 47, text: "Topics: sea")]
    )

    #expect(slots.map(\.number) == [1, 2, 3])
    #expect(slots[0].label == "main story text")
    #expect(slots[1].label.contains("status bar"))
    #expect(slots[1].label.contains("above the story"))
    #expect(slots[1].label.contains("1 row"))
    #expect(slots[2].label.contains("panel"))
    #expect(slots[2].label.contains("below the story"))
  }

  @Test("window 1 reads the last response; a status window reads its rows")
  func slotContent() throws {
    let slots = WindowInventory.slots(
      storyTop: 1,
      lastResponse: [line("You are in a field."), line("It is bright.")],
      statusWindows: [grid(id: 2, top: 0, rows: ["Score: 10", ""])],
      secondaryBuffers: []
    )

    #expect(slots[0].contentLines == ["You are in a field.", "It is bright."])
    // Blank grid rows are dropped from the readback.
    #expect(slots[1].contentLines == ["Score: 10"])
  }

  @Test("the windows readout numbers each slot by its label")
  func listReadout() throws {
    let slots = WindowInventory.slots(
      storyTop: 1, lastResponse: [line("x")],
      statusWindows: [grid(id: 2, top: 0, rows: ["Score: 10"])], secondaryBuffers: [])
    let readout = WindowInventory.listReadout(slots: slots)

    #expect(readout.title == "Windows")
    #expect(readout.lines.map(\.number) == [1, 2])
    #expect(readout.lines[0].text == "main story text")
  }
}
