import Foundation

/// Appends a word the user double-tapped in the story log to the current command,
/// with smart spacing — the typing-shortcut behavior from iOS Frotz. Pure, so the
/// spacing and punctuation rules are unit-tested without the WebView.
nonisolated enum CommandWordComposer {
  /// Append `rawWord` to `current`. Surrounding punctuation is trimmed (internal
  /// apostrophes/hyphens kept, so "don't" and "north-east" survive); a word that's
  /// empty after cleaning leaves the field unchanged. A single separating space is
  /// inserted — none when the field is empty or already ends with whitespace — and
  /// a trailing space is added so the next tap or keystroke continues cleanly.
  static func append(_ rawWord: String, to current: String) -> String {
    let word = clean(rawWord)
    guard !word.isEmpty else { return current }
    if current.isEmpty { return word + " " }
    if current.last?.isWhitespace == true { return current + word + " " }
    return current + " " + word + " "
  }

  /// Trim any non-alphanumeric characters off both ends, keeping the run intact in
  /// between (internal `'`/`’`/`-`). "sword." → "sword", "(north)" → "north",
  /// "..." → "".
  private static func clean(_ raw: String) -> String {
    var chars = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    while let first = chars.first, !first.isLetter, !first.isNumber { chars.removeFirst() }
    while let last = chars.last, !last.isLetter, !last.isNumber { chars.removeLast() }
    return String(chars)
  }
}
