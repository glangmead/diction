import Foundation

/// The free-vs-unlocked feature rules, in one pure place so they can be
/// unit-tested without StoreKit. `fullVersion` is the live entitlement from
/// `StoreManager`.
///
/// The non-voice experience is entirely free: any game plays, and narration
/// through the accessibility voice works without the purchase. The single
/// purchase (`com.luminous.diction.full`) buys the two invested-in voice
/// features — neural (Kokoro) narration and voice commands. One exception:
/// voice commands are free to try in a bundled game (ADR 0001), so a
/// prospective buyer can try the feature on a game we vouch for.
nonisolated enum DemoPolicy {
  /// Neural (Kokoro) narration requires the unlock. Auditioning voices in the
  /// picker is always free; this gates *narration* and the "Use neural voice"
  /// toggle.
  static func neuralVoiceUnlocked(fullVersion: Bool) -> Bool { fullVersion }

  /// Voice commands require the purchase — except in a bundled game, where they
  /// are free to try (ADR 0001). Keyed on the source, not the game's name, so a second
  /// bundled game gets the same treatment without touching this file.
  static func voiceCommandsAllowed(fullVersion: Bool, source: StoryFile.Source) -> Bool {
    fullVersion || source == .bundled
  }

  /// Neural narration is active only when the setting is on AND unlocked — so a
  /// lapsed entitlement (refund) cleanly falls back to the system voice rather
  /// than narrating with a paid voice.
  static func usesNeuralVoice(setting useKokoro: Bool, fullVersion: Bool) -> Bool {
    useKokoro && neuralVoiceUnlocked(fullVersion: fullVersion)
  }
}
