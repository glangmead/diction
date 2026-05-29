import Foundation

/// Curated vocabulary of words and short phrases that show up in most
/// interactive-fiction games. Merged with each story's auto-extracted
/// parser dictionary before being handed to `SFSpeechRecognizer` as
/// `contextualStrings`.
///
/// Why this exists: even when "west" is in the game's extracted dictionary,
/// `SFSpeechRecognizer`'s general-vocabulary prior often beats the
/// contextual-string bias for common English minimal pairs ("west"/"rest"/
/// "guest", "north"/"forth"). Listing these explicitly — and putting them
/// *first* in the contextual-strings list so they survive the recognizer's
/// effective ~100-item weight window — biases the recognizer harder.
///
/// Edit the lists freely as new games surface new useful vocabulary.
nonisolated enum IFCanonicalTerms {
  /// Cardinal / intercardinal directions and threshold verbs.
  /// Highest priority — these are the most often misheard.
  static let directions: [String] = [
    "north", "south", "east", "west",
    "northeast", "northwest", "southeast", "southwest",
    "up", "down",
    "in", "out",
    "enter", "exit", "leave"
  ]

  /// Core IF parser verbs accepted by virtually every game.
  static let verbs: [String] = [
    "look", "examine", "search", "read",
    "listen", "smell", "touch", "taste",
    "take", "get", "drop", "put", "place",
    "open", "close", "lock", "unlock",
    "push", "pull", "turn", "press", "move",
    "give", "show", "ask", "tell", "say",
    "attack", "kill", "fight", "hit", "throw", "break",
    "climb", "jump", "swim", "fly", "dig",
    "eat", "drink",
    "wear", "remove",
    "sleep", "wait", "sit", "stand",
    "save", "restore", "restart", "quit",
    "score", "inventory", "again", "undo",
    "yes", "no"
  ]

  /// Nouns that recur across many IF games. Add game-specific nouns here
  /// as the bundled catalog grows.
  static let commonNouns: [String] = [
    "lantern", "sword", "key", "door", "window",
    "wall", "floor", "ceiling",
    "mailbox", "leaflet", "letter", "book", "map", "scroll",
    "rope", "knife", "bag", "bottle", "box", "chest",
    "lamp", "torch", "candle", "match",
    "coin", "gold", "silver", "treasure",
    "troll", "grue", "thief", "wizard"
  ]

  /// Coordinator-command vocabulary. These are addressed to the app itself
  /// ("<wake word>, reread"), not to the game's parser. Biasing them ensures
  /// the recognizer hears the command verbs cleanly. The wake word itself is
  /// prepended separately by `VoiceCoordinator`, since it's user-configurable.
  static let coordinator: [String] = [
    "reread", "repeat", "again",
    "stop", "pause", "quiet",
    "faster", "slower",
    "speed up", "slow down"
  ]

  /// Ordered for `contextualStrings`: highest-bias terms first so they
  /// always survive the recognizer's truncation, regardless of how big
  /// the per-game dictionary is.
  static let all: [String] = coordinator + directions + verbs + commonNouns
}
