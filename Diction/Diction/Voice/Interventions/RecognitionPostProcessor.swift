import Foundation

/// Post-recognition rewrite built from the ASR interventions: N-best recovery
/// (swap a transcribed word the parser doesn't know for an alternative it does),
/// then forced corrections. Pure and `Sendable`.
nonisolated struct RecognitionPostProcessor: Sendable {
  let interventions: ASRInterventions

  /// Recover then correct. `knownWords` is the parser dictionary ∪ profile
  /// vocabulary, lowercased — the set recovery treats as "real words".
  func process(_ utterance: RecognizedUtterance, knownWords: Set<String>) -> String {
    var text = utterance.best
    if interventions.alternativesRecovery ?? false {
      text = recover(utterance, knownWords: knownWords)
    }
    for correction in interventions.corrections {
      text = correction.apply(to: text)
    }
    return text
  }

  /// For each word the parser doesn't know, swap in the first alternative it does.
  private func recover(_ utterance: RecognizedUtterance, knownWords: Set<String>) -> String {
    utterance.words.map { word -> String in
      guard !knownWords.contains(Self.normalize(word.best)) else { return word.best }
      return word.alternatives.first { knownWords.contains(Self.normalize($0)) } ?? word.best
    }
    .joined(separator: " ")
  }

  private static let strip = CharacterSet.punctuationCharacters.union(.whitespaces)

  private static func normalize(_ word: String) -> String {
    word.lowercased().trimmingCharacters(in: strip)
  }
}
