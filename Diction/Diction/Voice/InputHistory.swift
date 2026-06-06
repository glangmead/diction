import Foundation

/// Turns the session's chronological line-command log into the reverse-chron view
/// the `history` command reads back and `input N` addresses (1 = most recent).
/// Char keypresses never enter the log, so the numbering is contiguous over real
/// commands.
nonisolated enum InputHistory {
  /// The most recent commands, newest first, capped at `limit`.
  static func recent(_ history: [String], limit: Int = 20) -> [String] {
    history.suffix(limit).reversed()
  }

  /// The `history` answer: the recent commands numbered newest-first.
  static func readout(_ history: [String], limit: Int = 20) -> VoiceReadout {
    let lines = recent(history, limit: limit).enumerated().map { index, command in
      VoiceReadout.Line(number: index + 1, text: command)
    }
    return VoiceReadout(title: "Recent commands", lines: lines)
  }
}
