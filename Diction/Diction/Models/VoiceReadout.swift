import Foundation

/// A numbered list the voice layer both narrates and shows in the readout
/// overlay — the answer to `help`, `windows`, `history`, or `keywords`. The
/// overlay renders `title` + `lines`; `spokenText` is the same content flattened
/// into one speakable string, so the two channels can't diverge.
nonisolated struct VoiceReadout: Equatable {
  struct Line: Equatable {
    /// 1-based index for addressable lists (`window N`, `input N`); nil for the
    /// help list, whose rows aren't addressed by number.
    let number: Int?
    let text: String
  }

  let title: String
  let lines: [Line]

  /// Flattened narration: the title, then each line as `"N, text"` (numbered) or
  /// the bare text, joined by sentence breaks.
  var spokenText: String {
    let body = lines.map { line in
      if let number = line.number { return "\(number), \(line.text)" }
      return line.text
    }
    return ([title] + body).joined(separator: ". ") + "."
  }
}
