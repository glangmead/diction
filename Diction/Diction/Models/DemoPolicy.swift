import Foundation

/// The demo-vs-full feature rules, in one pure place so they can be unit-tested
/// without StoreKit. `fullVersion` is the live entitlement from `StoreManager`.
nonisolated enum DemoPolicy {
  /// Kokoro voices playable in demo: the first voice of each accent/gender group
  /// (US·F, US·M, UK·F, UK·M). All system `AVSpeechSynthesisVoice`s are free too,
  /// but they never reach this type — the system-voice picker isn't gated.
  static let demoKokoroVoiceIDs: Set<String> =
    ["af_heart", "am_michael", "bf_emma", "bm_george"]

  /// Demo plays only bundled games; full plays anything.
  static func isPlayable(_ story: StoryFile, fullVersion: Bool) -> Bool {
    fullVersion || story.source == .bundled
  }

  /// Call only with Kokoro voice IDs. System voices are never gated and never
  /// reach this function.
  static func isKokoroVoiceUnlocked(_ id: String, fullVersion: Bool) -> Bool {
    fullVersion || demoKokoroVoiceIDs.contains(id)
  }

  /// `stored` if unlocked, else the free default `af_heart` — so demo never
  /// narrates with a paid voice even if a locked ID is somehow stored (e.g.
  /// entitlement lost after a refund).
  static func effectiveKokoroVoice(_ stored: String, fullVersion: Bool) -> String {
    isKokoroVoiceUnlocked(stored, fullVersion: fullVersion) ? stored : "af_heart"
  }
}
