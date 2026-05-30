import Foundation
import FluidAudio

/// Lexicon-first text→IPA for the KokoroAne model.
///
/// Wraps FluidAudio's `StyleTTS2Phonemizer` (misaki `us_lexicon_cache.json`
/// lexicon + BART G2P fallback for OOV words) and adapts its output for KokoroAne:
///   - splits English clitics (possessives/contractions) whose whole form isn't
///     a lexicon entry but whose stem is — so "someone's" resolves "someone" from
///     the lexicon plus a `'s` ending, instead of the whole token mis-falling-back
///     to the neural G2P ("some-ee-onz");
///   - contracts misaki diphthong shorthand (`eɪ`→`A`, …) which StyleTTS2 expands,
///     back to the single-char tokens KokoroAne was trained on.
///
/// The result is ready for `KokoroAneManager.synthesizeFromPhonemes`.
struct KokoroPhonemizer: Sendable {

  private let phonemizer: StyleTTS2Phonemizer
  private let lexiconWords: Set<String>

  /// Load the misaki lexicon (read-only) from the bundled `kokoro/` dir, filtered
  /// to the KokoroAne vocab. Returns nil on any failure so the caller can fall
  /// back to the model's built-in per-word G2P.
  static func load(bundleRoot root: URL) async -> KokoroPhonemizer? {
    do {
      let allowed = try vocabTokens(bundleRoot: root)
      let cache = LexiconAssetCache()
      try await cache.ensureLoaded(
        kokoroDirectory: root.appendingPathComponent("kokoro", isDirectory: true),
        allowedTokens: allowed)
      let (lower, caseSensitive) = await cache.lexicons()
      let words = Set(lower.keys).union(caseSensitive.keys.map { $0.lowercased() })
      return KokoroPhonemizer(
        phonemizer: StyleTTS2Phonemizer(
          wordToPhonemes: lower, caseSensitiveWordToPhonemes: caseSensitive),
        lexiconWords: words)
    } catch {
      print("[kokoro] lexicon phonemizer unavailable (\(error)); using built-in G2P")
      return nil
    }
  }

  /// Text → KokoroAne-ready IPA. Phonemized token-by-token for clitic handling
  /// and weak-form function words.
  func phonemize(_ text: String) async throws -> String {
    let tokens = Self.tokenize(Self.normalizeNumbers(text))
    var parts: [String] = []
    for (index, token) in tokens.enumerated() {
      if let weak = Self.weakForm(token, nextWord: Self.nextWord(in: tokens, after: index)) {
        parts.append(weak)
      } else if let (stem, suffix) = splitClitic(token) {
        let stemIPA = try await phonemizer.phonemize(stem)
        parts.append(stemIPA + Self.cliticIPA(suffix, afterStem: stemIPA))
      } else {
        parts.append(try await phonemizer.phonemize(token))
      }
    }
    return Self.contractDiphthongs(parts.joined(separator: " "))
  }

  // MARK: - Weak-form function words

  /// The lexicon stores "the" and "a" in their stressed citation forms (`ði`
  /// "thee", `eɪ` "ay"), which sound wrong unstressed. Substitute the reduced
  /// forms: "a" → /ə/; "the" → /ðə/ before a consonant, /ði/ before a vowel.
  private static func weakForm(_ token: String, nextWord: String?) -> String? {
    switch token.lowercased() {
    case "a": return "ə"
    case "the": return (nextWord.map(startsWithVowelSound) ?? false) ? "ði" : "ðə"
    default: return nil
    }
  }

  /// Next token that contains a letter (skips punctuation), for "the" context.
  private static func nextWord(in tokens: [String], after index: Int) -> String? {
    tokens[(index + 1)...].first { $0.contains(where: \.isLetter) }
  }

  /// Approximate: true if the word starts with a vowel letter. Misses the rare
  /// consonant-sound-vowel-letter cases ("university", "hour").
  private static func startsWithVowelSound(_ word: String) -> Bool {
    guard let first = word.lowercased().first else { return false }
    return "aeiou".contains(first)
  }

  // MARK: - Clitics

  /// If `word` is a clitic form the lexicon doesn't know whole but whose stem it
  /// does, return (stem, suffix). Nil for words the lexicon has outright (so
  /// "it's" / "don't" aren't wrongly split).
  private func splitClitic(_ word: String) -> (stem: String, suffix: String)? {
    let lower = word.lowercased()
    if lexiconWords.contains(lower) { return nil }
    for suffix in ["n't", "'re", "'ve", "'ll", "'s", "'d", "'m"] where lower.hasSuffix(suffix) {
      let stem = String(word.dropLast(suffix.count))
      if !stem.isEmpty, lexiconWords.contains(stem.lowercased()) {
        return (stem, suffix)
      }
    }
    return nil
  }

  private static func cliticIPA(_ suffix: String, afterStem stemIPA: String) -> String {
    switch suffix {
    case "'s": return possessiveS(after: stemIPA)
    case "n't": return "nt"
    case "'re": return "ɚ"
    case "'ve": return "v"
    case "'ll": return "l"
    case "'d": return "d"
    case "'m": return "m"
    default: return ""
    }
  }

  /// English `'s` voicing: /ɪz/ after a sibilant, /s/ after a voiceless stop,
  /// else /z/. Looks at the last non-suprasegmental phoneme of the stem.
  private static func possessiveS(after stemIPA: String) -> String {
    guard let last = stemIPA.last(where: { !"ˈˌːˑ".contains($0) }) else { return "z" }
    if "szʃʒʧʤɕʑ".contains(last) { return "ɪz" }
    if "ptkfθ".contains(last) { return "s" }
    return "z"
  }

  // MARK: - Number normalization

  /// Replace digit runs with spoken words ("42"→"forty two", "21st"→"twenty
  /// first") so they hit the lexicon instead of the model's digit-blind G2P.
  /// Commas inside a number are treated as thousands separators ("1,000").
  private static func normalizeNumbers(_ text: String) -> String {
    let chars = Array(text)
    var out = ""
    var digits = ""
    var index = 0

    func flush(ordinal: Bool) {
      guard !digits.isEmpty else { return }
      // FluidAudio's SSML number speller (en_US_POSIX `NumberFormatter` +
      // ordinal handling). It hyphenates ("forty-two"); our per-word lexicon
      // lookup wants separate tokens, so split hyphens to spaces.
      let words = SayAsInterpreter.interpret(
        content: digits, interpretAs: ordinal ? "ordinal" : "cardinal", format: nil)
      out += words.replacingOccurrences(of: "-", with: " ")
      digits = ""
    }

    while index < chars.count {
      let char = chars[index]
      if char.isNumber {
        digits.append(char)
        index += 1
      } else if char == ",", !digits.isEmpty, index + 1 < chars.count, chars[index + 1].isNumber {
        index += 1  // thousands separator inside a number
      } else if !digits.isEmpty,
        let suffix = ["st", "nd", "rd", "th"].first(where: {
          String(chars[index...]).lowercased().hasPrefix($0)
        }) {
        flush(ordinal: true)
        index += suffix.count
      } else {
        flush(ordinal: false)
        out.append(char)
        index += 1
      }
    }
    flush(ordinal: false)
    return out
  }

  // MARK: - Tokenizing + diphthong contraction

  /// Mirrors `StyleTTS2Phonemizer`'s splitter: runs of letters/digits/`'`/`-`,
  /// with every other character its own token (so punctuation separates from
  /// adjacent words and clitic detection sees the bare word).
  private static func tokenize(_ text: String) -> [String] {
    var out: [String] = []
    var current = ""
    for char in text {
      if char.isWhitespace {
        if !current.isEmpty { out.append(current); current = "" }
      } else if char.isLetter || char.isNumber || char == "'" || char == "-" {
        current.append(char)
      } else {
        if !current.isEmpty { out.append(current); current = "" }
        out.append(String(char))
      }
    }
    if !current.isEmpty { out.append(current) }
    return out
  }

  /// `StyleTTS2Phonemizer` expands misaki diphthong shorthand to two IPA chars
  /// (for espeak-style training); the laishere KokoroAne model wants the
  /// shorthand. Contract it back so the model gets its native tokens.
  private static func contractDiphthongs(_ ipa: String) -> String {
    var result = ipa
    for (expanded, shorthand) in [("eɪ", "A"), ("oʊ", "O"), ("aɪ", "I"), ("ɔɪ", "Y"), ("aʊ", "W")] {
      result = result.replacingOccurrences(of: expanded, with: shorthand)
    }
    return result
  }

  // MARK: - Vocab

  /// The KokoroAne phoneme inventory (vocab.json keys), to filter lexicon tokens
  /// to what the model can encode.
  private static func vocabTokens(bundleRoot root: URL) throws -> Set<String> {
    let url = root.appendingPathComponent("kokoro-82m-coreml/ANE/vocab.json")
    let data = try Data(contentsOf: url)
    let map = try JSONDecoder().decode([String: Int].self, from: data)
    return Set(map.keys)
  }
}
