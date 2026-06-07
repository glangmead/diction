import Testing
import Foundation
@testable import Diction

@MainActor
private func misakiResourcesReady() -> Bool {
  guard let root = Bundle.main.url(forResource: "KokoroModels", withExtension: "bundle")?
    .appendingPathComponent("misaki", isDirectory: true) else { return false }
  DataResourcesUtil.bundleURL = root
  return !DataResourcesUtil.loadGold(british: false).isEmpty
}

// Regression: decimals were dropped because getSpecialCase mistook "5.50" for a
// dotted initialism, and getNumber didn't cover head-position single-dot decimals.
@Test("Decimal amounts are spoken, not dropped")
@MainActor
func decimalsAreSpoken() {
  #expect(misakiResourcesReady())
  let g2p = EnglishG2P(british: false, fallback: { _ in ("", 1) })
  let bare = g2p.phonemize(text: "it cost 5.50").0
  #expect(bare.contains("fˈIv") && bare.contains("fˈɪfti"), "5.50 → \(bare)")
  let priced = g2p.phonemize(text: "it cost $5.50").0
  #expect(priced.contains("fˈIv") && priced.contains("fˈɪfti"), "$5.50 → \(priced)")
}

// The dash → pause transform moved out of vendored EnglishG2P into our
// PausePolicy post-pass (see PausePolicyTests for the unit), so this exercises it
// through the full KokoroPhonemizer path where it now lives.
@Test("Standalone dash becomes a triple-semicolon pause; mid-compound dash is stripped")
func dashesHandled() async throws {
  let root = Bundle.main.url(forResource: "KokoroModels", withExtension: "bundle")!
  let phonemizer = try #require(await KokoroPhonemizer.load(bundleRoot: root))
  let out = try await phonemizer.phonemize("hey -- over here, my to-do list", british: false)
  #expect(!out.contains("—"), "raw em-dash present: \(out)")
  #expect(!out.contains("  "), "double space present: \(out)")
  #expect(out.contains("hˈA;;;"), "standalone dash not turned into ;;;: \(out)")
  #expect(out.contains("tudˈu"), "to-do not joined: \(out)")
}

@Test("Problem cases phonemize correctly through the full KokoroPhonemizer path")
func problemCorpus() async throws {
  let root = Bundle.main.url(forResource: "KokoroModels", withExtension: "bundle")!
  let phonemizer = try #require(await KokoroPhonemizer.load(bundleRoot: root))
  for (text, needle) in [
    ("to-do", "tudˈu"),
    ("co-op", "kˈOˌɑp"),
    ("e.g.", "ˌiʤˈi"),
    ("in 1776 we", "sˌɛvəntˈin"),  // year reading, not "one thousand…"
    ("at 3pm", "pˌiˈɛm")
  ] {
    let ipa = try await phonemizer.phonemize(text, british: false)
    #expect(ipa.contains(needle), "‘\(text)’ → \(ipa)")
  }
  // OOV: a word missing from the dicts must come back non-empty via the
  // StyleTTS2Phonemizer (CoreML BART) fallback, not get dropped.
  let oov = try await phonemizer.phonemize("Frobozz", british: false)
  #expect(!oov.trimmingCharacters(in: .whitespaces).isEmpty, "OOV dropped: ‘Frobozz’ → ‘\(oov)’")
}

// misaki's number tokenizer swallows a "%" glued to a number ("100%" → "one
// hundred"). The percent-sign textRule rewrites "%" to the word before G2P; this
// proves "100%" then phonemizes identically to "100 percent".
@Test("the percent-sign rule makes 100% read as 100 percent")
func percentRule() async throws {
  let root = Bundle.main.url(forResource: "KokoroModels", withExtension: "bundle")!
  var phonemizer = try #require(await KokoroPhonemizer.load(bundleRoot: root))
  let target = try await phonemizer.phonemize("100 percent", british: false)
  #expect(!target.isEmpty)
  phonemizer.tts = TTSInterventions(
    pronunciations: [],
    textRules: [TextRule(id: "percent", match: #"\s*%"#, action: .replace, with: " percent")],
    pausePolicy: nil)
  let withRule = try await phonemizer.phonemize("100%", british: false)
  #expect(withRule == target, "‘100%’ → ‘\(withRule)’ vs ‘100 percent’ → ‘\(target)’")
}
