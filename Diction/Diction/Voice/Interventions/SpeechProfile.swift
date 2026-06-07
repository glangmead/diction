import Foundation

/// The resolved speech-intervention profile — TTS and ASR slices — consumed by the
/// phonemizer and the voice coordinator. A `Sendable` value type so it can cross
/// into the phonemizer's off-main work. Built by `SpeechProfileStore` from the
/// bundled `global.json` overlaid with the user's, via `merging(_:)`.
nonisolated struct SpeechProfile: Sendable, Equatable, Codable {
  var schemaVersion: Int
  var tts: TTSInterventions
  var asr: ASRInterventions

  static let empty = SpeechProfile(schemaVersion: 1, tts: .empty, asr: .empty)

  init(schemaVersion: Int = 1, tts: TTSInterventions = .empty, asr: ASRInterventions = .empty) {
    self.schemaVersion = schemaVersion
    self.tts = tts
    self.asr = asr
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    tts = try container.decodeIfPresent(TTSInterventions.self, forKey: .tts) ?? .empty
    asr = try container.decodeIfPresent(ASRInterventions.self, forKey: .asr) ?? .empty
  }

  /// Decode a profile from one layer's JSON.
  static func decode(_ data: Data) throws -> SpeechProfile {
    try JSONDecoder().decode(SpeechProfile.self, from: data)
  }

  /// Overlay `overlay` onto self, overlay winning per the slice merge rules.
  func merging(_ overlay: SpeechProfile) -> SpeechProfile {
    SpeechProfile(
      schemaVersion: schemaVersion,
      tts: tts.merging(overlay.tts),
      asr: asr.merging(overlay.asr))
  }
}
