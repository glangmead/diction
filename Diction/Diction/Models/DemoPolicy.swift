import Foundation

/// The free-vs-unlocked feature rules, in one pure place so they can be
/// unit-tested without StoreKit. `fullVersion` is the live entitlement from
/// `StoreManager`.
///
/// The non-voice experience is entirely free: any game plays, and narration
/// through Apple's on-board voices works without the unlock. The single IAP
/// (`com.luminous.diction.full`) buys the two invested-in voice features —
/// neural (Kokoro) narration and speak-to-command.
nonisolated enum DemoPolicy {
  /// Neural (Kokoro) narration requires the unlock. Auditioning voices in the
  /// picker is always free; this gates *narration* and the "Use neural voice"
  /// toggle.
  static func neuralVoiceUnlocked(fullVersion: Bool) -> Bool { fullVersion }

  /// Speak-to-command ("Play with my voice") requires the unlock.
  static func voiceInputUnlocked(fullVersion: Bool) -> Bool { fullVersion }

  /// Neural narration is active only when the setting is on AND unlocked — so a
  /// lapsed entitlement (refund) cleanly falls back to the system voice rather
  /// than narrating with a paid voice.
  static func usesNeuralVoice(setting useKokoro: Bool, fullVersion: Bool) -> Bool {
    useKokoro && neuralVoiceUnlocked(fullVersion: fullVersion)
  }
}
