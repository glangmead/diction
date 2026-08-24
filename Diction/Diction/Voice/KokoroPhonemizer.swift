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

  /// The resolved TTS interventions (pronunciations, textRules, pausePolicy) from
  /// the speech profile. `.empty` until the engine sets it; the pause transform
  /// that used to live in vendored `EnglishG2P` now rides `pausePolicy` here
  /// (default reproduces it byte-for-byte), and the ZORK hardcode is now the
  /// bundled `zork-casing` textRule.
  var tts: TTSInterventions = .empty

  /// Points the vendored loader at the bundled dictionaries, seeds the OOV G2P
  /// cache, and returns a phonemizer — or nil if either the dictionaries are
  /// missing or the G2P assets can't be staged (without them every OOV word would
  /// silently vanish from narration).
  static func load(bundleRoot: URL) async -> KokoroPhonemizer? {
    DataResourcesUtil.bundleURL = bundleRoot.appendingPathComponent("misaki", isDirectory: true)
    guard !DataResourcesUtil.loadGold(british: false).isEmpty else {
      print("[kokoro] misaki dictionaries missing; falling back to built-in G2P")
      return nil
    }
    do {
      try seedG2PCacheIfNeeded(fromBundleRoot: bundleRoot)
    } catch {
      print("[kokoro] G2P assets couldn't be staged: \(error); falling back to built-in G2P")
      return nil
    }
    return KokoroPhonemizer(oov: StyleTTS2Phonemizer())
  }

  /// Copy the shared G2P assets (`G2PEncoder.mlmodelc`, `G2PDecoder.mlmodelc`,
  /// `g2p_vocab.json`) from the bundle into `<caches>/fluidaudio/Models/kokoro/`
  /// if absent. FluidAudio's `G2PModel` (the OOV fallback here, and the KokoroAne
  /// English path) reads G2P only from that fixed cache location, so pointing it
  /// at the bundle is not enough. Idempotent; cheap once seeded.
  static func seedG2PCacheIfNeeded(fromBundleRoot root: URL) throws {
    let fileManager = FileManager.default
    guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      throw CocoaError(.fileNoSuchFile)
    }
    let dest = caches.appendingPathComponent("fluidaudio/Models/kokoro", isDirectory: true)
    let src = root.appendingPathComponent("kokoro", isDirectory: true)
    let required = ["G2PEncoder.mlmodelc", "G2PDecoder.mlmodelc", "g2p_vocab.json"]

    let allPresent = required.allSatisfy {
      fileManager.fileExists(atPath: dest.appendingPathComponent($0).path)
    }
    if allPresent { return }

    try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
    for name in required {
      let from = src.appendingPathComponent(name)
      let target = dest.appendingPathComponent(name)
      if fileManager.fileExists(atPath: target.path) { continue }
      try fileManager.copyItem(at: from, to: target)
    }
  }

  /// Text → KokoroAne IPA. `british` selects the GB dictionaries.
  func phonemize(_ text: String, british: Bool) async throws -> String {
    // Pre-G2P interventions: textRules (incl. zork-casing) then pronunciation
    // rewrites (ipa → in-band `[word](/ipa/)`, say → respelling).
    let text = tts.preprocessText(text)

    // Pass 1: run misaki to discover words the lexicon missed.
    let collector = OOVCollector()
    _ = EnglishG2P(british: british, fallback: { token in collector.add(token.text); return ("", 1) })
      .phonemize(text: text)

    // Resolve each OOV word with the neural G2P, normalized to misaki's tokens.
    var cache: [String: String] = [:]
    for word in collector.words {
      let raw: String
      if let remainder = Self.mcNameRemainder(word) {
        // The neural G2P swallows the consonant in "McB…"/"McW…" (it hears
        // "McCain"); pronouncing the remainder alone keeps it, prefixed /mək/.
        let rest = await neuralPhonemes(for: remainder)
        raw = rest.isEmpty ? "" : "mək" + rest
      } else {
        raw = await neuralPhonemes(for: word)
      }
      cache[word] = raw
        .replacingOccurrences(of: "ɾ", with: "T")
        .replacingOccurrences(of: "ʔ", with: "t")
    }

    // Pass 2: final phonemization, fallback served from the cache. The pause
    // policy (em-dash → pause tokens, etc.) is applied here, post-G2P, rather than
    // inside vendored EnglishG2P.
    let phonemes = EnglishG2P(british: british, fallback: { token in (cache[token.text] ?? "", 1) })
      .phonemize(text: text).0
    return (tts.pausePolicy ?? .default).apply(toPhonemes: phonemes)
  }

  /// One word through the neural G2P. A failure (typically the G2P assets missing
  /// from FluidAudio's cache dir) is logged rather than swallowed, because the
  /// only symptom otherwise is a word silently absent from the narration.
  private func neuralPhonemes(for word: String) async -> String {
    do {
      return try await oov.phonemize(word)
    } catch {
      DiagnosticsLog.g2pFailure(word: word, error: "\(error)")
      return ""
    }
  }

  /// `Mc` + an uppercase consonant other than C/K/Q is a Scottish/Irish surname
  /// whose consonant is pronounced (`McBain` = /mək/ + "Bain"). C/K/Q merge into a
  /// single /k/ (`McKay`, `McCain`) and vowels attach to the `c` (`McArthur`), so
  /// those are left to the neural G2P, which gets them right.
  private static let mcSplitInitials: Set<Character> = [
    "B", "D", "F", "G", "H", "J", "L", "M", "N", "P", "R", "S", "T", "V", "W", "X", "Y", "Z"
  ]

  /// For a `Mc`-name whose consonant the neural G2P would otherwise swallow,
  /// returns the part after `Mc` (`"McBain"` → `"Bain"`); nil otherwise.
  static func mcNameRemainder(_ word: String) -> String? {
    guard word.hasPrefix("Mc"), word.count > 2 else { return nil }
    let initial = word[word.index(word.startIndex, offsetBy: 2)]
    guard mcSplitInitials.contains(initial) else { return nil }
    return String(word.dropFirst(2))
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
