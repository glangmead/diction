import AVFoundation

/// The audio-session parameters for a listening (mic-on) session, derived from the
/// user's input choice and the live output context. A plain value so the routing
/// policy — historically one hard-coded `.playAndRecord` + `.defaultToSpeaker`
/// line in `SpeechRecognizer` — is unit-testable without audio hardware.
///
/// `SpeechRecognizer.startEngine()` applies it: category (always `.playAndRecord`)
/// + `mode` + `options`, an optional `setPreferredInput` by UID, and whether to
/// enable the voice-processing I/O unit.
struct ListeningSessionConfig: Equatable {
  var mode: AVAudioSession.Mode
  var options: AVAudioSession.CategoryOptions
  /// UID of the input port to pin via `setPreferredInput`, or nil to let the
  /// system choose from the allowed routes.
  var preferredInputUID: String?
  /// Whether to enable voice-processing (echo cancellation). Off only in the
  /// split-device case — Bluetooth A2DP output plus built-in-mic capture — where
  /// VPIO would force a call-quality route and the echo path (narration in the
  /// user's ears, mic on the phone) is negligible anyway.
  var enableVoiceProcessing: Bool

  /// Category is always `.playAndRecord` while listening.
  static let category: AVAudioSession.Category = .playAndRecord

  /// What the recognizer hands the shared session back as when it stops: always a
  /// real category change away from `.playAndRecord`, which is what clears iOS's
  /// post-VPIO gain reduction. See `NarrationSessionConfig` for the story.
  static let restoredOnStop = NarrationSessionConfig.standard

  /// Safe fallback used before the first real configuration: built-in mic, loud
  /// speaker, echo cancellation on.
  static let `default` = ListeningSessionConfig(
    mode: .default,
    options: [.duckOthers, .defaultToSpeaker],
    preferredInputUID: nil,
    enableVoiceProcessing: true)

  /// The routing policy. Pure — no `AVAudioSession` access — so it's fully tested.
  ///
  /// - `.builtInOnly`: force the loud speaker (not the receiver), built-in mic.
  /// - `.wired`: leave routing alone; the wired headset carries both directions.
  /// - `.bluetooth` with the built-in mic explicitly chosen: keep the Bluetooth
  ///   device on high-quality A2DP output and capture on the phone mic — so NO
  ///   `.allowBluetoothHFP` (which would grab the HFP route for input and collapse
  ///   output to call quality), and VPIO off.
  /// - `.bluetooth` otherwise (automatic, or the Bluetooth mic chosen): allow both
  ///   HFP and A2DP. With both set the system prefers HFP, so the AirPods do both
  ///   directions at call quality. No `.defaultToSpeaker` — forcing the speaker was
  ///   the jump-off-AirPods bug.
  static func make(
    choice: AudioInputChoice,
    output: OutputContext,
    preferredInputUID: String?
  ) -> ListeningSessionConfig {
    switch output {
    case .builtInOnly:
      return ListeningSessionConfig(
        mode: .default,
        options: [.duckOthers, .defaultToSpeaker],
        preferredInputUID: preferredInputUID,
        enableVoiceProcessing: true)
    case .wired:
      return ListeningSessionConfig(
        mode: .default,
        options: [.duckOthers],
        preferredInputUID: preferredInputUID,
        enableVoiceProcessing: true)
    case .bluetooth:
      if case .port(_, .builtInMic) = choice {
        return ListeningSessionConfig(
          mode: .default,
          options: [.duckOthers, .allowBluetoothA2DP],
          preferredInputUID: preferredInputUID,
          enableVoiceProcessing: false)
      }
      return ListeningSessionConfig(
        mode: .default,
        options: [.duckOthers, .allowBluetoothHFP, .allowBluetoothA2DP],
        preferredInputUID: preferredInputUID,
        enableVoiceProcessing: true)
    }
  }
}
