import Foundation

/// A pronunciation override for one word. Either `ipa` (Kokoro-shorthand IPA,
/// same alphabet as the gold dictionary and the in-band `[word](/…/)` syntax) or
/// `say` (a respelling re-run through G2P, for authors who don't write IPA).
nonisolated struct PronEntry: Sendable, Equatable, Codable {
  let word: String
  var ipa: String?
  var say: String?
}
