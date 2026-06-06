import Foundation

/// Pulls the highlighted words out of game output for the `keywords` command. A
/// run qualifies as a keyword when its resolved weight is bold (Blue Lacuna's
/// `user1`/`user2` styles, folded into `attributes.fontWeight` by the style
/// resolver) or it carries a hyperlink. Italic emphasis is excluded — verified
/// against the Blue Lacuna capture, where it marks ordinary prose, not keywords.
nonisolated enum KeywordScanner {
  private static let trimmed = CharacterSet(charactersIn: " \n\t.,;:!?\"'()[]")

  /// The keyword phrases in `entries`, de-duplicated case-insensitively in
  /// first-seen order.
  static func keywords(in entries: [StyledText]) -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    for entry in entries {
      for run in entry.runs where isKeyword(run) {
        let word = run.text.trimmingCharacters(in: trimmed)
        guard !word.isEmpty, seen.insert(word.lowercased()).inserted else { continue }
        ordered.append(word)
      }
    }
    return ordered
  }

  /// The `keywords` answer: the highlighted words listed.
  static func readout(_ words: [String]) -> VoiceReadout {
    VoiceReadout(title: "Keywords", lines: words.map { VoiceReadout.Line(number: nil, text: $0) })
  }

  private static func isKeyword(_ run: StyledText.Run) -> Bool {
    run.hyperlink != nil || run.attributes.fontWeight?.lowercased() == "bold"
  }
}
