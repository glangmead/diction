import Foundation
import NaturalLanguage

/// Pure sentence chunking for Kokoro narration, kept out of `KokoroSpeechEngine`
/// (like `KokoroPCM`) so the logic is unit-testable without the CoreML models.
///
/// The model synthesizes one clip per chunk, so chunking exists to start audio
/// before the whole passage is synthesized and to keep each clip's IPA under the
/// 510-phoneme cap. The earlier hand-rolled split on every "." fragmented
/// decimals ("3.14" → "3." + "14") and abbreviations ("Mr." → its own clip), and
/// emitted lone-period chunks from ellipses ("Well..." → "Well.", ".", ".") that
/// the model voiced as a stray syllable at sentence boundaries. `NLTokenizer`'s
/// sentence unit (ICU boundaries) handles all three correctly; we then drop any
/// piece with no spoken content so the model is never handed bare punctuation.
///
/// ICU also splits unconditionally after "?" and "!" (UAX #29 treats them as
/// sentence terminators with no lowercase-continuation exception, unlike "."),
/// so quoted dialogue like `"City of Doors?" you shout` is cut from its tag and
/// each half gets sentence-final intonation. We undo that by merging any piece
/// whose first letter is lowercase back into the previous one — a lowercase
/// start marks a continuation, not a new sentence.
enum KokoroText {
  static func sentences(_ text: String, maxChars: Int = 240) -> [String] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = trimmed

    var pieces: [String] = []
    tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
      let piece = trimmed[range].trimmingCharacters(in: .whitespacesAndNewlines)
      // Skip pieces with nothing to say (a stray "...", "—", or quotation mark);
      // synthesizing bare punctuation is what produced the stray "vuh" syllable.
      guard piece.contains(where: { $0.isLetter || $0.isNumber }) else { return true }
      // Re-join a continuation (lowercase first letter, e.g. a dialogue tag after
      // a quoted "?"/"!") onto the sentence ICU split it from.
      if !pieces.isEmpty, beginsAsContinuation(piece) {
        pieces[pieces.count - 1] += " " + piece
      } else {
        pieces.append(piece)
      }
      return true
    }

    var result: [String] = []
    for sentence in pieces {
      if sentence.count <= maxChars {
        result.append(sentence)
      } else {
        result.append(contentsOf: wrap(sentence, maxChars: maxChars))
      }
    }
    return result
  }

  /// True when the first cased letter is lowercase — the piece continues the
  /// previous sentence rather than starting a new one. Leading quotes, brackets,
  /// and digits are skipped to reach that letter.
  private static func beginsAsContinuation(_ piece: String) -> Bool {
    for char in piece where char.isLetter {
      return char.isLowercase
    }
    return false
  }

  private static func wrap(_ sentence: String, maxChars: Int) -> [String] {
    var pieces: [String] = []
    var line = ""
    for word in sentence.split(separator: " ") {
      if line.isEmpty {
        line = String(word)
      } else if line.count + 1 + word.count <= maxChars {
        line += " " + word
      } else {
        pieces.append(line)
        line = String(word)
      }
    }
    if !line.isEmpty { pieces.append(line) }
    return pieces
  }
}
