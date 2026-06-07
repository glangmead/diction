import Foundation

/// A text-normalization rule applied to a chunk before phonemization. Data, not
/// code: the only Turing-adjacent surface is the regex `match`; `action` is a
/// closed enum. `apply(to:)` is added in the textRules phase.
nonisolated struct TextRule: Sendable, Equatable, Codable {
  /// Closed set of transforms a rule may request.
  enum Action: String, Sendable, Codable {
    /// Insert spaces between the digits of the match, so each is spoken alone.
    case spaceDigits
    /// Replace the match with the literal `with` string.
    case replace
  }

  let id: String
  /// Pipeline stage; v1 only supports `before-g2p`. Decoded from the `where` key.
  var stage: String
  /// Regular expression matched against the chunk text.
  let match: String
  let action: Action
  /// Replacement text for `.replace`.
  var with: String?

  enum CodingKeys: String, CodingKey {
    case id, match, action, with
    case stage = "where"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    match = try container.decode(String.self, forKey: .match)
    action = try container.decode(Action.self, forKey: .action)
    with = try container.decodeIfPresent(String.self, forKey: .with)
    stage = try container.decodeIfPresent(String.self, forKey: .stage) ?? "before-g2p"
  }

  init(id: String, stage: String = "before-g2p", match: String, action: Action, with: String? = nil) {
    self.id = id
    self.stage = stage
    self.match = match
    self.action = action
    self.with = with
  }

  /// Apply this rule to a chunk of text. Pure; invalid regex passes through.
  func apply(to text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: match) else { return text }
    let full = NSRange(text.startIndex..., in: text)
    switch action {
    case .replace:
      return regex.stringByReplacingMatches(in: text, range: full, withTemplate: with ?? "")
    case .spaceDigits:
      // Replace each match with its characters space-joined. Reverse so earlier
      // match ranges stay valid as we mutate from the end.
      var result = text
      for match in regex.matches(in: text, range: full).reversed() {
        guard let range = Range(match.range, in: result) else { continue }
        result.replaceSubrange(range, with: result[range].map(String.init).joined(separator: " "))
      }
      return result
    }
  }
}
