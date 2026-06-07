import Foundation

/// The ASR slice of a speech profile. Decode-tolerant like `TTSInterventions`.
nonisolated struct ASRInterventions: Sendable, Equatable, Codable {
  var vocabulary: [String]
  /// Absent (nil) in an overlay means "don't touch the base setting".
  var alternativesRecovery: Bool?
  var corrections: [Correction]

  static let empty = ASRInterventions(vocabulary: [], alternativesRecovery: nil, corrections: [])

  init(vocabulary: [String], alternativesRecovery: Bool?, corrections: [Correction]) {
    self.vocabulary = vocabulary
    self.alternativesRecovery = alternativesRecovery
    self.corrections = corrections
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    vocabulary = try container.decodeIfPresent([String].self, forKey: .vocabulary) ?? []
    alternativesRecovery = try container.decodeIfPresent(Bool.self, forKey: .alternativesRecovery)
    corrections = try container.decodeIfPresent([Correction].self, forKey: .corrections) ?? []
  }

  /// Overlay `overlay` onto self (overlay wins): vocabulary + corrections union
  /// (de-duplicated, order preserved with overlay's new entries appended),
  /// `alternativesRecovery` taken from the overlay when it sets one.
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
      corrections: merged)
  }
}
