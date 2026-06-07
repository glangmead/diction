import Foundation

/// A post-recognition rewrite applied to the transcribed text — the deterministic
/// backstop for words Apple never offers as an N-best alternative. `apply(to:)` is
/// added in the ASR-recovery phase.
nonisolated struct Correction: Sendable, Equatable, Codable {
  enum Mode: String, Sendable, Codable {
    /// `from` matches a whole word (case-insensitive), replaced by `to`.
    case wholeWord
    /// `from` is a regular expression.
    case regex
  }

  let from: String
  /// Replacement text. JSON key `to`; named `into` to satisfy the identifier-length lint.
  let into: String
  var mode: Mode

  enum CodingKeys: String, CodingKey {
    case from, mode
    case into = "to"
  }

  init(from: String, into: String, mode: Mode = .wholeWord) {
    self.from = from
    self.into = into
    self.mode = mode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    from = try container.decode(String.self, forKey: .from)
    into = try container.decode(String.self, forKey: .into)
    mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .wholeWord
  }

  /// Rewrite `text`: `wholeWord` replaces case-insensitive whole-word matches of
  /// `from` with the literal `into`; `regex` treats `from` as a pattern and `into`
  /// as a template (supports `$1` backreferences). Pure; invalid regex passes through.
  func apply(to text: String) -> String {
    let full = NSRange(text.startIndex..., in: text)
    switch mode {
    case .wholeWord:
      let pattern = "\\b\(NSRegularExpression.escapedPattern(for: from))\\b"
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return text
      }
      return regex.stringByReplacingMatches(
        in: text, range: full, withTemplate: NSRegularExpression.escapedTemplate(for: into))
    case .regex:
      guard let regex = try? NSRegularExpression(pattern: from) else { return text }
      return regex.stringByReplacingMatches(in: text, range: full, withTemplate: into)
    }
  }
}
