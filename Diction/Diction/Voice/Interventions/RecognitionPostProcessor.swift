import Foundation

/// Post-recognition rewrite built from the ASR interventions: N-best recovery
/// (swap a transcribed word the parser doesn't know for an alternative it does),
/// then forced corrections. Pure and `Sendable`.
nonisolated struct RecognitionPostProcessor: Sendable {
  let interventions: ASRInterventions

  /// Recover then correct. `knownWords` is the parser dictionary ∪ profile
  /// vocabulary, lowercased — the set recovery treats as "real words". `log`, when
  /// supplied, receives a human-readable trace (the heard words, each word's
  /// candidates and the recovery decision, any corrections, and the result) — the
  /// "what is this component doing" diagnostic.
  func process(
    _ utterance: RecognizedUtterance, knownWords: Set<String>, log: ((String) -> Void)? = nil
  ) -> String {
    let recovery = interventions.alternativesRecovery ?? false
    let join = interventions.joinSpelledWords ?? false
    guard recovery || join || log != nil || !interventions.corrections.isEmpty else {
      return utterance.best
    }
    log?("heard: \"\(utterance.best)\" [\(utterance.words.count) word(s)]")
    var words = utterance.words
    if join { words = joinSpelledRuns(words, knownWords: knownWords, log: log) }
    let resolved = words.map { word -> String in
      let candidates = word.alternatives.joined(separator: ", ")
      let known = knownWords.contains(Self.normalize(word.best))
      if recovery, !known,
         let alt = word.alternatives.first(where: { knownWords.contains(Self.normalize($0)) }) {
        log?("  '\(word.best)' → '\(alt)' (recovered) | candidates: [\(candidates)]")
        return alt
      }
      let reason = known ? "known" : (recovery ? "no known candidate" : "recovery off")
      log?("  '\(word.best)' kept (\(reason)) | candidates: [\(candidates)]")
      return word.best
    }
    var text = resolved.joined(separator: " ")
    for correction in interventions.corrections {
      let before = text
      text = correction.apply(to: text)
      if text != before {
        log?("correction \(correction.from)→\(correction.into): \"\(before)\" → \"\(text)\"")
      }
    }
    log?("result: \"\(text)\"")
    return text
  }

  /// Merge runs of single-letter words whose concatenation is a known word,
  /// taking the longest known prefix of each run (so "W N N F G" with "WNNF" known
  /// becomes "WNNF" + "G"). The merged word carries itself as its sole alternative.
  private func joinSpelledRuns(
    _ words: [RecognizedUtterance.Word], knownWords: Set<String>, log: ((String) -> Void)?
  ) -> [RecognizedUtterance.Word] {
    var result: [RecognizedUtterance.Word] = []
    var index = 0
    while index < words.count {
      var runEnd = index
      while runEnd < words.count, Self.isSingleLetter(words[runEnd].best) { runEnd += 1 }
      var merged = false
      var end = runEnd
      while end - index >= 2 {                    // longest known prefix, runs of 2+
        let joined = words[index..<end].map(\.best).joined()
        if knownWords.contains(Self.normalize(joined)) {
          log?("  joined '\(words[index..<end].map(\.best).joined(separator: " "))' → '\(joined)' (known)")
          result.append(RecognizedUtterance.Word(best: joined, alternatives: [joined]))
          index = end
          merged = true
          break
        }
        end -= 1
      }
      if !merged {
        result.append(words[index])
        index += 1
      }
    }
    return result
  }

  private static func isSingleLetter(_ text: String) -> Bool {
    text.count == 1 && (text.first?.isLetter ?? false)
  }

  private static let strip = CharacterSet.punctuationCharacters.union(.whitespaces)

  private static func normalize(_ word: String) -> String {
    word.lowercased().trimmingCharacters(in: strip)
  }
}
