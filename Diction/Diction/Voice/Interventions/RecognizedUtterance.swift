import Foundation

/// A finalized recognition result carrying per-word alternatives, so the
/// post-processor can recover an acronym Apple ranked below a real word (it heard
/// "POF" but offered "PEOF"). Built by `SpeechRecognizer` from the best
/// transcription's segments and their `alternativeSubstrings`.
nonisolated struct RecognizedUtterance: Sendable, Equatable {
  struct Word: Sendable, Equatable {
    let best: String
    /// Candidate spellings for this position, `best` first.
    let alternatives: [String]
  }

  let words: [Word]

  /// The best transcription as a single string (words joined by spaces).
  var best: String { words.map(\.best).joined(separator: " ") }

  /// A plain utterance with no alternatives — for the typed-input path.
  static func plain(_ text: String) -> RecognizedUtterance {
    RecognizedUtterance(words: text.split(separator: " ").map {
      Word(best: String($0), alternatives: [String($0)])
    })
  }
}
