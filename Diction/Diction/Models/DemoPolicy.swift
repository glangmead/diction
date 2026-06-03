import Foundation

/// The demo-vs-full feature rules, in one pure place so they can be unit-tested
/// without StoreKit. `fullVersion` is the live entitlement from `StoreManager`.
nonisolated enum DemoPolicy {
  /// Kokoro voices playable in demo: the first voice of each accent/gender group
  /// (US·F, US·M, UK·F, UK·M). All system `AVSpeechSynthesisVoice`s are free too,
  /// but they never reach this type — the system-voice picker isn't gated.
  static let demoKokoroVoiceIDs: Set<String> =
    ["af_heart", "am_michael", "bf_emma", "bm_george"]

  enum VoiceRole { case game, echo }

  /// Demo plays only bundled games; full plays anything.
  static func isPlayable(_ story: StoryFile, fullVersion: Bool) -> Bool {
    fullVersion || story.source == .bundled
  }

  /// Call only with Kokoro voice IDs. System voices are never gated and never
  /// reach this function.
  static func isKokoroVoiceUnlocked(_ id: String, fullVersion: Bool) -> Bool {
    fullVersion || demoKokoroVoiceIDs.contains(id)
  }

  /// `stored` if unlocked, else the role's free fallback — so demo never narrates
  /// with a paid voice even if a locked ID is somehow stored (e.g. entitlement
  /// lost after a refund). `af_heart` is the game default; `am_michael` contrasts
  /// as the echo voice.
  static func effectiveKokoroVoice(
    _ stored: String,
    role: VoiceRole,
    fullVersion: Bool
  ) -> String {
    if isKokoroVoiceUnlocked(stored, fullVersion: fullVersion) { return stored }
    switch role {
    case .game: return "af_heart"
    case .echo: return "am_michael"
    }
  }
}
