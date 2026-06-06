import Testing
@testable import Diction

@Suite("Voice readout")
struct VoiceReadoutTests {
  @Test("numbered lines narrate as 'title. N, text.'")
  func numberedSpokenText() {
    let readout = VoiceReadout(
      title: "Recent commands",
      lines: [.init(number: 1, text: "north"), .init(number: 2, text: "up")]
    )
    #expect(readout.spokenText == "Recent commands. 1, north. 2, up.")
  }

  @Test("unnumbered lines narrate as plain sentences")
  func unnumberedSpokenText() {
    let readout = VoiceReadout(
      title: "Voice commands",
      lines: [.init(number: nil, text: "stop: Stop the narration")]
    )
    #expect(readout.spokenText == "Voice commands. stop: Stop the narration.")
  }

  @Test("an empty readout narrates just its title")
  func emptySpokenText() {
    #expect(VoiceReadout(title: "Nothing here", lines: []).spokenText == "Nothing here.")
  }
}

@Suite("StyledText narration")
struct StyledTextNarrationTests {
  @Test("a narration entry round-trips its text into plainText")
  func roundTrips() {
    #expect(StyledText.narration("hello there").map(\.plainText).joined() == "hello there")
  }
}

@Suite("Help readout")
struct HelpReadoutTests {
  @Test("help lists every catalog command")
  func listsEveryCommand() {
    let help = VoiceCommandCatalog.helpReadout()
    #expect(help.lines.count == VoiceCommandCatalog.entries.count)
  }

  @Test("help names plain commands and the usage of numbered ones")
  func namesCommands() {
    let help = VoiceCommandCatalog.helpReadout()
    #expect(help.lines.contains { $0.text.contains("stop") })
    #expect(help.lines.contains { $0.text.contains("window [number]") })
    #expect(help.lines.contains { $0.text.contains("keywords") })
  }
}
