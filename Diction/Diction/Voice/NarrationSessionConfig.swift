import AVFoundation

/// The audio-session parameters for narration with no recognizer live: a plain
/// `.playback` session that ducks other audio. The counterpart of
/// `ListeningSessionConfig`, and the one definition shared by every site that
/// configures the session for narration — the narrators (`SpeechSynthesizer`,
/// the Kokoro audition) and the recognizer, which hands the session back in this
/// configuration when it stops (`ListeningSessionConfig.restoredOnStop`).
///
/// Why the recognizer restores it, and why narrators must not infer "recognizer
/// live" from the session's category (impl #02): after voice-processing I/O has
/// run under `.playAndRecord`, iOS keeps a hidden output-gain reduction that
/// outlives VPIO and is cleared only by a category change. A stopped recognizer
/// used to leave `.playAndRecord` behind; the narrators saw a "compatible"
/// category, skipped `setCategory`, and played near-mute under a record-capable
/// session with no I/O unit behind it. Only a live recognizer may own
/// `.playAndRecord`.
struct NarrationSessionConfig {
  let category: AVAudioSession.Category
  let mode: AVAudioSession.Mode
  let options: AVAudioSession.CategoryOptions

  /// The only narration configuration the app uses.
  static let standard = NarrationSessionConfig(
    category: .playback,
    mode: .default,
    options: [.duckOthers])

  /// Whether a narrator should apply the narration configuration before playing.
  /// Pure, so the decision is unit-tested without audio hardware. A live
  /// recognizer owns the session and is never disturbed; otherwise apply unless
  /// `.playback` is already in place. `recognizerLive` is the recognizer's own
  /// state (`SpeechRecognizer.ownsAudioSession`), never the session's category.
  static func shouldApply(recognizerLive: Bool, currentCategory: AVAudioSession.Category) -> Bool {
    !recognizerLive && currentCategory != .playback
  }

  /// Set this configuration's category on `session`. Does not activate.
  func apply(to session: any AudioSessionControlling) throws {
    try session.setCategory(category, mode: mode, options: options)
  }
}
