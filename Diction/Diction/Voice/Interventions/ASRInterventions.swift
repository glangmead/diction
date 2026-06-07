import Foundation

/// The ASR slice of a speech profile. Decode-tolerant like `TTSInterventions`.
nonisolated struct ASRInterventions: Sendable, Equatable, Codable {
  var vocabulary: [String]
  /// Absent (nil) in an overlay means "don't touch the base setting".
  var alternativesRecovery: Bool?
  /// When set, merge runs of single-letter words whose concatenation is a known
  /// parser word ("W N N F" → "WNNF" iff the game knows "WNNF"). Apple segments a
  /// spelled acronym into letters; this rejoins it. Dictionary-guided, so it only
  /// ever merges into a real word. Absent (nil) → don't touch the base setting.
  var joinSpelledWords: Bool?
  var corrections: [Correction]

  static let empty = ASRInterventions(
    vocabulary: [], alternativesRecovery: nil, joinSpelledWords: nil, corrections: [])

  init(
    vocabulary: [String], alternativesRecovery: Bool?,
    joinSpelledWords: Bool? = nil, corrections: [Correction]
  ) {
    self.vocabulary = vocabulary
    self.alternativesRecovery = alternativesRecovery
    self.joinSpelledWords = joinSpelledWords
    self.corrections = corrections
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    vocabulary = try container.decodeIfPresent([String].self, forKey: .vocabulary) ?? []
    alternativesRecovery = try container.decodeIfPresent(Bool.self, forKey: .alternativesRecovery)
    joinSpelledWords = try container.decodeIfPresent(Bool.self, forKey: .joinSpelledWords)
    corrections = try container.decodeIfPresent([Correction].self, forKey: .corrections) ?? []
  }

  /// Overlay `overlay` onto self (overlay wins): vocabulary + corrections union
  /// (de-duplicated, order preserved with overlay's new entries appended);
  /// `alternativesRecovery` / `joinSpelledWords` taken from the overlay when set.
  func merging(_ overlay: ASRInterventions) -> ASRInterventions {
    var vocab = vocabulary
    var seen = Set(vocabulary)
    for word in overlay.vocabulary where seen.insert(word).inserted {
      vocab.append(word)
    }
    var merged = corrections
    for correction in overlay.corrections where !merged.contains(correction) {
      merged.append(correction)
    }
    return ASRInterventions(
      vocabulary: vocab,
      alternativesRecovery: overlay.alternativesRecovery ?? alternativesRecovery,
      joinSpelledWords: overlay.joinSpelledWords ?? joinSpelledWords,
      corrections: merged)
  }
}
