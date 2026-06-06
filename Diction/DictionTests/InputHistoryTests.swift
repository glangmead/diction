import Testing
@testable import Diction

/// `InputHistory` turns the session's chronological line-command log into the
/// reverse-chron list the `history` command reads and `input N` addresses
/// (1 = most recent).
@Suite("Input history")
struct InputHistoryTests {
  @Test("recent reverses chronological order so 1 is the most recent")
  func reverses() {
    #expect(InputHistory.recent(["north", "up", "look"]) == ["look", "up", "north"])
  }

  @Test("recent caps at the limit, keeping the newest")
  func caps() {
    let history = (1...25).map(String.init)
    let recent = InputHistory.recent(history, limit: 20)
    #expect(recent.count == 20)
    #expect(recent.first == "25")
    #expect(recent.last == "6")
  }

  @Test("the readout numbers recent commands, newest first")
  func readout() {
    let readout = InputHistory.readout(["north", "up", "look"])
    #expect(readout.title == "Recent commands")
    #expect(readout.lines.map(\.number) == [1, 2, 3])
    #expect(readout.lines[0].text == "look")
    #expect(readout.lines[2].text == "north")
  }
}
