import Foundation

/// Per-punctuation pause lengths, as counts of the model's `;` pause token (the
/// model makes pauses from `;`/`,` tokens, not inserted silence). `apply(toPhonemes:)`
/// is added in the pausePolicy phase. `.default` reproduces today's narration: a
/// dash becomes `;;; `, and comma/semicolon/colon stay as the single model-native
/// token (count 1 = unchanged). Decode-tolerant: omitted fields fall to the default.
nonisolated struct PausePolicy: Sendable, Equatable, Codable {
  var comma: Int
  var semicolon: Int
  var colon: Int
  var dash: Int

  static let `default` = PausePolicy(comma: 1, semicolon: 1, colon: 1, dash: 3)

  /// Apply the pause policy to an assembled Kokoro phoneme string. Relocated from
  /// the old vendored `EnglishG2P` em-dash hack: a whitespace-flanked em-dash
  /// becomes `dash` pause tokens (`;`), a mid-compound em-dash is dropped, and
  /// comma/semicolon/colon gain `count - 1` extra `;` tokens. `.default` reproduces
  /// the old output exactly. Pure string transform.
  func apply(toPhonemes phonemes: String) -> String {
    // Expand original punctuation first (before the em-dash run is inserted, so its
    // `;` tokens aren't re-expanded).
    var result = phonemes
    result = expanding(result, punctuation: ",", count: comma)
    result = expanding(result, punctuation: ";", count: semicolon)
    result = expanding(result, punctuation: ":", count: colon)
    // A whitespace-flanked em-dash becomes `dash` pause tokens; a mid-compound one
    // is dropped so the word flows.
    let dashRun = String(repeating: ";", count: max(0, dash))
    result = result.replacingOccurrences(
      of: #"\s+—+\s*|\s*—+\s+"#, with: dashRun + " ", options: .regularExpression)
    result = result.replacingOccurrences(of: "—", with: "")
    while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
    return result.trimmingCharacters(in: .whitespaces)
  }

  /// Append `count - 1` pause tokens after each occurrence of `punctuation`.
  private func expanding(_ string: String, punctuation: String, count: Int) -> String {
    guard count > 1 else { return string }
    return string.replacingOccurrences(
      of: punctuation, with: punctuation + String(repeating: ";", count: count - 1))
  }

  init(comma: Int, semicolon: Int, colon: Int, dash: Int) {
    self.comma = comma
    self.semicolon = semicolon
    self.colon = colon
    self.dash = dash
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let fallback = PausePolicy.default
    comma = try container.decodeIfPresent(Int.self, forKey: .comma) ?? fallback.comma
    semicolon = try container.decodeIfPresent(Int.self, forKey: .semicolon) ?? fallback.semicolon
    colon = try container.decodeIfPresent(Int.self, forKey: .colon) ?? fallback.colon
    dash = try container.decodeIfPresent(Int.self, forKey: .dash) ?? fallback.dash
  }
}
