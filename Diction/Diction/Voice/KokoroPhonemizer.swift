import Foundation
import FluidAudio

/// Lexicon-first text→IPA for KokoroAne, backed by the vendored misaki core
/// (`Voice/Misaki/`): tokenization + text normalization + POS-aware lexicon,
/// emitting Kokoro shorthand directly. Out-of-vocabulary words — the rare tail
/// the dictionaries miss — are resolved by FluidAudio's CoreML G2P
/// (`StyleTTS2Phonemizer` with an empty lexicon ⇒ always neural), normalized to
/// misaki's token convention. Result is ready for `synthesizeFromPhonemes`.
struct KokoroPhonemizer: Sendable {
  private let oov: StyleTTS2Phonemizer  // empty lexicon ⇒ pure neural G2P

  /// Points the vendored loader at the bundled dictionaries and returns a
  /// phonemizer, or nil if the dictionaries are missing.
  static func load(bundleRoot: URL) async -> KokoroPhonemizer? {
    DataResourcesUtil.bundleURL = bundleRoot.appendingPathComponent("misaki", isDirectory: true)
    guard !DataResourcesUtil.loadGold(british: false).isEmpty else {
      print("[kokoro] misaki dictionaries missing; falling back to built-in G2P")
      return nil
    }
    return KokoroPhonemizer(oov: StyleTTS2Phonemizer())
  }

  /// Text → KokoroAne IPA. `british` selects the GB dictionaries.
  func phonemize(_ text: String, british: Bool) async throws -> String {
    // Pass 1: run misaki to discover words the lexicon missed.
    let collector = OOVCollector()
    _ = EnglishG2P(british: british, fallback: { token in collector.add(token.text); return ("", 1) })
      .phonemize(text: text)

    // Resolve each OOV word with the neural G2P, normalized to misaki's tokens.
    var cache: [String: String] = [:]
    for word in collector.words {
      let raw = (try? await oov.phonemize(word)) ?? ""
      cache[word] = raw
        .replacingOccurrences(of: "ɾ", with: "T")
        .replacingOccurrences(of: "ʔ", with: "t")
    }

    // Pass 2: final phonemization, fallback served from the cache.
    return EnglishG2P(british: british, fallback: { token in (cache[token.text] ?? "", 1) })
      .phonemize(text: text).0
  }
}

/// Thread-safe collector for misaki's synchronous discovery pass.
private final class OOVCollector: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var words: [String] = []
  func add(_ word: String) {
    lock.lock()
    if !words.contains(word) { words.append(word) }
    lock.unlock()
  }
}
