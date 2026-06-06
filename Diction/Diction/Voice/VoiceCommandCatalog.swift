import Foundation

/// Single source of truth for the wake-word command vocabulary: it both parses an
/// utterance into a `VoiceCoordinator.CoordinatorCommand` and supplies the
/// human-readable summaries the `help` readout renders, so the two can't drift.
///
/// Plain entries match an utterance against a fixed trigger list; numbered entries
/// (`window N`, `input N`) match a prefix followed by a number — spoken as digits
/// (`window 2`), a number word (`window two`), or glued by the recognizer
/// (`window2`).
nonisolated enum VoiceCommandCatalog {
  enum Match {
    case plain(VoiceCoordinator.CoordinatorCommand)
    case numbered(prefix: String, make: @Sendable (Int) -> VoiceCoordinator.CoordinatorCommand)
  }

  struct Entry {
    /// Canonical trigger first, then synonyms; canonical is what `help` displays.
    let triggers: [String]
    /// Usage hint shown in `help` for numbered commands, e.g. `"window [number]"`.
    let usage: String?
    /// One-line description for the `help` readout.
    let summary: String
    let match: Match
  }

  /// The full command vocabulary, in the order `help` reads it back.
  static let entries: [Entry] = [
    Entry(triggers: ["stop", "pause", "quiet", "shut up", "be quiet"],
          usage: nil, summary: "Stop the narration.", match: .plain(.stop)),
    Entry(triggers: ["reread", "repeat", "again", "say that again", "say again"],
          usage: nil, summary: "Read the last response again.", match: .plain(.reread)),
    Entry(triggers: ["faster", "speed up", "speak faster", "talk faster"],
          usage: nil, summary: "Speak faster.", match: .plain(.faster)),
    Entry(triggers: ["slower", "slow down", "speak slower", "talk slower"],
          usage: nil, summary: "Speak slower.", match: .plain(.slower)),
    Entry(triggers: ["help", "commands"],
          usage: nil, summary: "List the voice commands.", match: .plain(.help)),
    Entry(triggers: ["windows", "panels"],
          usage: nil, summary: "List the game's windows.", match: .plain(.windows)),
    Entry(triggers: ["window"], usage: "window [number]",
          summary: "Read a window's contents aloud.",
          match: .numbered(prefix: "window", make: { .window($0) })),
    Entry(triggers: ["history", "inputs"],
          usage: nil, summary: "List your recent commands.", match: .plain(.history)),
    Entry(triggers: ["input"], usage: "input [number]",
          summary: "Repeat one of your recent commands to the game.",
          match: .numbered(prefix: "input", make: { .input($0) })),
    Entry(triggers: ["keywords", "bolded", "bold"],
          usage: nil, summary: "List the highlighted words in the last passage.",
          match: .plain(.keywords))
  ]

  /// The `help` answer: one line per command (canonical name or usage hint,
  /// then its summary), in catalog order. Single source with the parser.
  static func helpReadout() -> VoiceReadout {
    let lines = entries.map { entry in
      VoiceReadout.Line(number: nil, text: "\(entry.usage ?? entry.triggers[0]): \(entry.summary)")
    }
    return VoiceReadout(title: "Voice commands", lines: lines)
  }

  /// Parse a wake-word-stripped utterance into a command, or nil if none matches.
  /// Plain triggers are matched first so `windows` wins over the `window` prefix.
  static func parse(_ text: String) -> VoiceCoordinator.CoordinatorCommand? {
    let normalized = normalize(text)
    guard !normalized.isEmpty else { return nil }

    for entry in entries {
      if case .plain(let command) = entry.match, entry.triggers.contains(normalized) {
        return command
      }
    }
    for entry in entries {
      if case .numbered(let prefix, let make) = entry.match,
         normalized.hasPrefix(prefix),
         let number = parseNumber(String(normalized.dropFirst(prefix.count))) {
        return make(number)
      }
    }
    return nil
  }

  /// Lowercase, trim, and collapse internal whitespace runs to single spaces, so
  /// the recognizer's spacing ("  Window   3 ") doesn't defeat matching.
  private static func normalize(_ text: String) -> String {
    text.lowercased()
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  /// Parse the tail after a numbered prefix into an integer — bare digits ("2",
  /// "15"), a glued digit ("2" from "window2"), or a number word ("two",
  /// "fifteen"). Returns nil when the tail isn't a number.
  private static func parseNumber(_ tail: String) -> Int? {
    let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let value = Int(trimmed) { return value }
    return numberWords[trimmed]
  }

  /// Spoken number words the recognizer might emit for a window/input index.
  /// Covers 0–20; larger values arrive as bare digits.
  private static let numberWords: [String: Int] = [
    "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
    "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
    "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20
  ]
}
