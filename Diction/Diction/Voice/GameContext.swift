import Foundation

/// Provides text context to the voice layer (recognition hints and AI prompts).
/// Conformed to by `InterpreterSession` and, in the future, a narrative-log
/// type for Ironsworn-style games.
@MainActor
protocol GameContext {
  /// Words to bias speech recognition toward (verbs, nouns, place names).
  var contextualStrings: [String] { get }

  /// Recent game text to feed to the AI normalizer as context.
  var recentTranscript: String { get }
}

extension InterpreterSession: GameContext {
  var contextualStrings: [String] {
    Array(dictionary)
  }

  var recentTranscript: String {
    transcript.suffix(10).map(\.plainText).joined()
  }
}
