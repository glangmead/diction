import Foundation

/// The TTS slice of a speech profile. Decode-tolerant: any omitted key falls to an
/// empty/absent default, so a partial overlay file is valid.
nonisolated struct TTSInterventions: Sendable, Equatable, Codable {
  var pronunciations: [PronEntry]
  var textRules: [TextRule]
  /// Absent (nil) in an overlay means "don't touch the base policy".
  var pausePolicy: PausePolicy?

  static let empty = TTSInterventions(pronunciations: [], textRules: [], pausePolicy: nil)

  /// Pre-G2P text transform: apply textRules (in order), then pronunciations
  /// (`ipa` → in-band `[word](/ipa/)`, `say` → respelling substitution). Pure.
  func preprocessText(_ text: String) -> String {
    var result = text
    for rule in textRules where rule.stage == "before-g2p" {
      result = rule.apply(to: result)
    }
    for entry in pronunciations {
      result = applyPronunciation(entry, to: result)
    }
    return result
  }

  /// Rewrite whole-word (case-insensitive) matches of a pronunciation entry: an
  /// `ipa` entry into the in-band `[word](/ipa/)` override `EnglishG2P` already
  /// parses; a `say` entry into its respelling.
  private func applyPronunciation(_ entry: PronEntry, to text: String) -> String {
    let replacement: String
    if let ipa = entry.ipa {
      replacement = "[\(entry.word)](/\(ipa)/)"
    } else if let say = entry.say {
      replacement = say
    } else {
      return text
    }
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: entry.word))\\b"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return text
    }
    let full = NSRange(text.startIndex..., in: text)
    return regex.stringByReplacingMatches(
      in: text, range: full, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
  }

  /// Pronunciation lookup keyed by lowercased word; later entries win on duplicates.
  var pronunciationsByWord: [String: PronEntry] {
    var result: [String: PronEntry] = [:]
    for entry in pronunciations { result[entry.word.lowercased()] = entry }
    return result
  }

  init(pronunciations: [PronEntry], textRules: [TextRule], pausePolicy: PausePolicy?) {
    self.pronunciations = pronunciations
    self.textRules = textRules
    self.pausePolicy = pausePolicy
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    pronunciations = try container.decodeIfPresent([PronEntry].self, forKey: .pronunciations) ?? []
    textRules = try container.decodeIfPresent([TextRule].self, forKey: .textRules) ?? []
    pausePolicy = try container.decodeIfPresent(PausePolicy.self, forKey: .pausePolicy)
  }

  /// Overlay `overlay` onto self (overlay wins): pronunciations replace by lowercased
  /// word (new appended), textRules replace by id (new appended in order), pausePolicy
  /// taken from the overlay when it sets one.
  func merging(_ overlay: TTSInterventions) -> TTSInterventions {
    var prons = pronunciations
    for entry in overlay.pronunciations {
      if let index = prons.firstIndex(where: { $0.word.lowercased() == entry.word.lowercased() }) {
        prons[index] = entry
      } else {
        prons.append(entry)
      }
    }
    var rules = textRules
    for rule in overlay.textRules {
      if let index = rules.firstIndex(where: { $0.id == rule.id }) {
        rules[index] = rule
      } else {
        rules.append(rule)
      }
    }
    return TTSInterventions(
      pronunciations: prons, textRules: rules, pausePolicy: overlay.pausePolicy ?? pausePolicy)
  }
}
