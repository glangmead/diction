import Foundation
import NaturalLanguage

/// Extracts vocabulary from recent game-response transcript entries for
/// per-utterance biasing of `SFSpeechRecognizer.contextualStrings`. The
/// idea: when the player is about to speak, the words they're most
/// likely to say are the words the game just showed them.
///
/// Uses Apple's `NLTagger` with `.lexicalClass` to identify nouns, verbs,
/// adjectives, and adverbs — the IF-relevant parts of speech. Articles,
/// prepositions, and pronouns don't need biasing (they're already
/// universally recognized).
///
/// Skips entries created by `StyledText.userInput(_:)` — those are the
/// player's own echoed commands, not new content from the game.
nonisolated enum TranscriptVocabulary {
  /// Returns deduplicated lowercased words from the most recent game
  /// responses, ordered by appearance. Cap arguments are conservative
  /// defaults — tune in callers if the recognizer's contextual-strings
  /// budget is tight.
  static func extract(
    from transcript: [StyledText],
    lookback: Int = 20,
    maxWords: Int = 150
  ) -> [String] {
    let responses = transcript.suffix(lookback).filter { !$0.isUserInput }
    let combined = responses.map(\.plainText).joined(separator: " ")
    guard !combined.isEmpty else { return [] }

    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.string = combined

    var seen: Set<String> = []
    var ordered: [String] = []
    tagger.enumerateTags(
      in: combined.startIndex..<combined.endIndex,
      unit: .word,
      scheme: .lexicalClass
    ) { tag, tokenRange in
      guard let tag, Self.relevantClasses.contains(tag) else { return true }
      let word = String(combined[tokenRange]).lowercased()
      // 1-char tokens are almost always articles, prepositions, or noise
      // letters the tagger misidentified.
      guard word.count >= 2, seen.insert(word).inserted else { return true }
      ordered.append(word)
      return ordered.count < maxWords
    }
    return ordered
  }

  private static let relevantClasses: Set<NLTag> = [
    .noun, .verb, .adjective, .adverb, .otherWord
  ]
}
