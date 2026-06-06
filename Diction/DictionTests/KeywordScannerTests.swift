import Testing
@testable import Diction

/// `KeywordScanner` pulls the highlighted words out of the last game output —
/// bold-weight runs (Blue Lacuna's `user1`/`user2` keywords) or hyperlinked runs.
/// Italic emphasis is deliberately excluded: in the motivating game it marks
/// ordinary prose emphasis, not keywords.
@Suite("Keyword scanner")
struct KeywordScannerTests {
  private func bold(_ text: String) -> StyledText.Run {
    .init(text: text, style: .user2, attributes: StyleAttributes(fontWeight: "bold"))
  }

  @Test("bold-weight runs are keywords")
  func boldRuns() {
    let line = StyledText(runs: [
      .init(text: "You see ", style: .normal),
      bold("Progue"),
      .init(text: " here.", style: .normal)
    ])
    #expect(KeywordScanner.keywords(in: [line]) == ["Progue"])
  }

  @Test("hyperlinked runs are keywords even without bold")
  func hyperlinkRuns() {
    let line = StyledText(runs: [.init(text: "the sea", style: .normal, hyperlink: 5)])
    #expect(KeywordScanner.keywords(in: [line]) == ["the sea"])
  }

  @Test("italic emphasis and normal text are not keywords")
  func nonKeywords() {
    let line = StyledText(runs: [
      .init(text: "He ", style: .normal),
      .init(text: "whispered", style: .emphasized, attributes: StyleAttributes(fontStyle: "italic")),
      .init(text: " softly", style: .normal)
    ])
    #expect(KeywordScanner.keywords(in: [line]).isEmpty)
  }

  @Test("keywords are de-duplicated case-insensitively in first-seen order")
  func dedup() {
    let lines = [
      StyledText(runs: [bold("Progue"), .init(text: " and ", style: .normal), bold("Way")]),
      StyledText(runs: [bold("progue")])
    ]
    #expect(KeywordScanner.keywords(in: lines) == ["Progue", "Way"])
  }

  @Test("surrounding punctuation is trimmed from a keyword run")
  func trimsPunctuation() {
    let line = StyledText(runs: [bold("Progue,")])
    #expect(KeywordScanner.keywords(in: [line]) == ["Progue"])
  }

  @Test("the readout titles and lists the words")
  func readout() {
    let readout = KeywordScanner.readout(["Progue", "Way"])
    #expect(readout.title == "Keywords")
    #expect(readout.lines.map(\.text) == ["Progue", "Way"])
  }
}
