import Foundation

/// Wake-word routing: decides whether an utterance is addressed to the
/// coordinator ("game, stop"), to the game's parser, or should be dropped.
/// Pure and static — reads no coordinator state — so it lives apart from the
/// coordinator's lifecycle glue and is tested directly (`DispatchDecisionTests`).
extension VoiceCoordinator {
  nonisolated enum CoordinatorCommand: Equatable {
    case reread
    case stop
    case faster
    case slower
    case help
    case windows
    case window(Int)
    case history
    case input(Int)
    case keywords
  }

  nonisolated enum DispatchDecision: Equatable {
    case coordinator(CoordinatorCommand)
    case game
    case ignore
  }

  /// Pure routing decision. `.game` means "forward the original text to the
  /// parser"; `.ignore` covers addressed-but-unparsed and bare-while-narrating.
  static func decide(text: String, wakeWord: String, isNarrating: Bool) -> DispatchDecision {
    let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let wake = normalizedWakeWord(wakeWord)
    if isAddressed(lower, wakeWord: wake) {
      if let command = VoiceCommandCatalog.parse(stripWakeWord(from: lower, wakeWord: wake)) {
        return .coordinator(command)
      }
      return .ignore
    }
    // The recognizer often runs the wake word and a short command together into
    // a single token ("game stop" → "GameStop"), leaving no separator for
    // `isAddressed`. Accept that ONLY when the remainder after the wake-word
    // prefix is itself a known command — otherwise a real game word that merely
    // starts with the wake word (e.g. "gamekeeper") must still reach the parser.
    if lower.hasPrefix(wake),
       let command = VoiceCommandCatalog.parse(String(lower.dropFirst(wake.count))) {
      return .coordinator(command)
    }
    // A bare utterance while narrating is dropped — whether the game wants a
    // line or a single key, only "<wake> …" commands interrupt narration. The
    // recognizer would otherwise mistake the narration audio for input.
    return isNarrating ? .ignore : .game
  }

  static func normalizedWakeWord(_ raw: String?) -> String {
    let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.isEmpty ? "game" : trimmed
  }

  /// Characters allowed between the wake word and the command that follows it
  /// ("game, stop" / "game stop" / "game: stop"). Single source of truth for
  /// both addressing and stripping so the two can't drift apart.
  private static let wakeWordSeparators: Set<Character> = [" ", ",", ".", "?", "!", ":"]

  private static func isAddressed(_ lower: String, wakeWord: String) -> Bool {
    if lower == wakeWord { return true }
    guard lower.hasPrefix(wakeWord) else { return false }
    let nextIndex = lower.index(lower.startIndex, offsetBy: wakeWord.count)
    guard nextIndex < lower.endIndex else { return true }
    return wakeWordSeparators.contains(lower[nextIndex])
  }

  private static func stripWakeWord(from lower: String, wakeWord: String) -> String {
    let after = lower.dropFirst(wakeWord.count)
    let trimmed = after.drop(while: { wakeWordSeparators.contains($0) })
    return String(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
