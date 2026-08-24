import Foundation
import AVFoundation

/// Speaks game output and command echoes. Echoes use a lower pitch so the
/// user can hear them as distinct from the game's voice.
@Observable
@MainActor
final class SpeechSynthesizer: NSObject {
  private(set) var isSpeaking = false

  /// TTS is unavailable in the Simulator: the neural voice renders into the
  /// Simulator's audio output as a loud screech (no ANE, broken audio path), so
  /// every speech entry point no-ops there and the UI disables + turns off the
  /// narration toggle. Real devices are unaffected.
  static let isSimulator: Bool = {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
  }()
  var isAvailable: Bool { !Self.isSimulator }

  /// True while the neural voice model is loading (cold start can take ~15 s on
  /// device). Lets the game UI show a loading affordance; always false when the
  /// neural path is off (or in the Simulator), since there's no load to wait on.
  var isPreparingVoice: Bool { isAvailable && useKokoro && kokoro.state == .preparing }

  private let synthesizer = AVSpeechSynthesizer()
  private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
  /// Set by `stop()` so an in-flight narration pass halts at the next entry
  /// rather than skipping to the following sentence. Reset when a pass begins.
  private var isStopped = false

  /// Spike: neural Kokoro engine. Used when `useKokoro` is on and the model
  /// loads; otherwise the AVSpeechSynthesizer path below runs unchanged.
  /// Replaceable so a game can adopt the app-level shared engine warmed on the
  /// library (see `useSharedEngine`); defaults to a private instance for any
  /// path that never adopts one (e.g. tests).
  private(set) var kokoro = KokoroSpeechEngine()

  /// Live full-version entitlement, injected by `VoiceCoordinator.useEntitlement`.
  /// Defaults to demo so any path that never wires it (e.g. tests) stays gated.
  var isFullVersion: @MainActor () -> Bool = { false }

  /// Whether a recognizer currently owns the shared audio session, injected by
  /// `VoiceCoordinator`. Defaults to "no" so a synthesizer with no coordinator
  /// (e.g. tests) configures the session for itself.
  var isRecognizerLive: @MainActor () -> Bool = { false }

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speakCommandEcho(_ command: String) async {
    guard isAvailable else { return }
    activatePlaybackSession()
    if useKokoro {
      await kokoro.prepareIfNeeded()
      if kokoro.isReady {
        isStopped = false
        isSpeaking = true
        defer { isSpeaking = false }
        // One voice for everything: echoes use the same neural voice as narration.
        await kokoro.speak(command, voice: kokoroGameVoice, speed: kokoroSpeed)
        return
      }
    }
    let utterance = AVSpeechUtterance(string: command)
    utterance.voice = selectedVoice()
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.pitchMultiplier = 0.85
    utterance.preUtteranceDelay = 0.1
    utterance.postUtteranceDelay = 0.4
    await enqueue(utterance)
  }

  /// Speaks a sequence of styled entries as one interruptible pass, applying
  /// minor prosody from each run's style. `stop()` halts the whole pass — not
  /// just the current sentence — by setting `isStopped`, which this loop checks
  /// before every utterance.
  func speak(_ entries: [StyledText]) async {
    guard isAvailable else { return }
    DiagnosticsLog.ttsEvent("speak-begin", pending: pendingContinuations.count, speaking: isSpeaking)
    defer { DiagnosticsLog.ttsEvent("speak-end", pending: pendingContinuations.count, speaking: isSpeaking) }
    activatePlaybackSession()
    isStopped = false
    if useKokoro {
      await kokoro.prepareIfNeeded()
      if kokoro.isReady {
        await speakViaKokoro(entries)
        return
      }
      print("[kokoro] not ready (\(kokoro.statusDescription)) — using system voice")
    }
    await speakViaSystem(entries)
  }

  /// The AVSpeechSynthesizer pass (fallback engine). Style → prosody lives in
  /// `systemUtterance` so this stays a simple interruptible loop.
  private func speakViaSystem(_ entries: [StyledText]) async {
    for entry in entries {
      if isStopped { return }
      for run in entry.runs {
        if isStopped { return }
        let speakable = Self.cleanForSpeech(run.text)
        guard !speakable.isEmpty else { continue }
        await enqueue(systemUtterance(text: speakable, style: run.style))
      }
    }
  }

  private func systemUtterance(text: String, style: RemGlkUpdate.TextStyle) -> AVSpeechUtterance {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = selectedVoice()
    utterance.rate = speechRate
    switch style {
    case .header, .subheader:
      utterance.rate = speechRate * 0.9
      utterance.preUtteranceDelay = 0.3
      utterance.postUtteranceDelay = 0.3
    case .emphasized:
      utterance.pitchMultiplier = 1.1
    case .alert, .note:
      utterance.preUtteranceDelay = 0.2
    default:
      break
    }
    return utterance
  }

  func stop() {
    isStopped = true
    synthesizer.stopSpeaking(at: .immediate)
    kokoro.stop()
    isSpeaking = false
    for continuation in pendingContinuations {
      continuation.resume()
    }
    pendingContinuations.removeAll()
    DiagnosticsLog.ttsEvent("stop", pending: pendingContinuations.count, speaking: isSpeaking)
  }

  /// Kick the Kokoro model load early (cold start ~2-3s) so the opening
  /// narration doesn't pay for it. Call from the game view's appear.
  func warmUpKokoro() {
    guard isAvailable, useKokoro else { return }
    Task { await kokoro.prepareIfNeeded() }
  }

  /// Adopt the app-level shared engine (warmed on the library by `VoiceWarmer`)
  /// so opening a game reuses the already-loaded model instead of starting a
  /// second cold load. Call before any narration.
  func useSharedEngine(_ engine: KokoroSpeechEngine) {
    kokoro = engine
    kokoro.ttsInterventions = ttsInterventions
  }

  /// Resolved TTS interventions from the speech profile; forwarded to the Kokoro
  /// engine (and re-applied if the engine is later swapped via `useSharedEngine`).
  private var ttsInterventions: TTSInterventions = .empty

  func applyTTSInterventions(_ tts: TTSInterventions) {
    ttsInterventions = tts
    kokoro.ttsInterventions = tts
  }

  // MARK: - Kokoro pass

  /// Speak each entry's plain text through Kokoro as one interruptible pass.
  /// `isStopped` is honored between entries; `KokoroSpeechEngine` chunks each
  /// entry into sentences internally.
  private func speakViaKokoro(_ entries: [StyledText]) async {
    print("[kokoro] narrating via neural voice '\(kokoroGameVoice)'")
    isSpeaking = true
    defer { isSpeaking = false }
    for entry in entries {
      if isStopped { return }
      let text = Self.cleanForSpeech(entry.plainText)
      guard !text.isEmpty else { continue }
      await kokoro.speak(text, voice: kokoroGameVoice, speed: kokoroSpeed)
    }
  }

  // MARK: - Internals

  /// Ensure an active, playback-capable audio session before narrating. A live
  /// recognizer owns the session and is left alone; otherwise narration runs
  /// under `NarrationSessionConfig`, set here unless already in place. Mirrors
  /// `KokoroSpeechEngine.ensureSessionForPlayback`.
  private func activatePlaybackSession() {
    let session = AVAudioSession.sharedInstance()
    if NarrationSessionConfig.shouldApply(
      recognizerLive: isRecognizerLive(), currentCategory: session.category) {
      try? NarrationSessionConfig.standard.apply(to: session)
    }
    try? session.setActive(true)
  }

  private func enqueue(_ utterance: AVSpeechUtterance) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      pendingContinuations.append(continuation)
      isSpeaking = true
      DiagnosticsLog.ttsEvent("enqueue", pending: pendingContinuations.count, speaking: isSpeaking)
      synthesizer.speak(utterance)
    }
  }

  private var speechRate: Float {
    let stored = UserDefaults.standard.float(forKey: "speechRate")
    return stored > 0 ? Float(stored) : AVSpeechUtteranceDefaultSpeechRate
  }

  /// Use the neural voice only when the setting is on AND the unlock is owned.
  /// Default off: neural narration is a paid feature, so a free user narrates
  /// through the system voice and a refunded owner cleanly falls back to it.
  private var useKokoro: Bool {
    let setting = UserDefaults.standard.object(forKey: "useKokoro") as? Bool ?? false
    return DemoPolicy.usesNeuralVoice(setting: setting, fullVersion: isFullVersion())
  }

  private var kokoroGameVoice: String {
    // Reaching here implies neural is unlocked (see `useKokoro`), so the stored
    // voice is used as-is — every Kokoro voice is available to an owner.
    let id = UserDefaults.standard.string(forKey: "kokoroVoiceId") ?? ""
    return id.isEmpty ? "af_heart" : id
  }

  /// Kokoro speed from the shared Settings rate, so `faster` / `slower` and the
  /// rate slider track across both engines.
  private var kokoroSpeed: Float {
    KokoroSpeechEngine.speed(forStoredRate: speechRate)
  }

  private var resolvedDefaultVoiceId: String?
  private var didResolveDefaultVoice = false

  /// The resolved default voice (best installed English), computed once per run. A
  /// newly installed voice only appears after an app relaunch anyway (`speechVoices()`
  /// is stale within a process), so re-enumerating per utterance would buy nothing
  /// and just sit on the synthesis hot path. See `SystemVoiceCatalog`.
  private func defaultVoiceId() -> String? {
    if !didResolveDefaultVoice {
      resolvedDefaultVoiceId = SystemVoiceCatalog.defaultIdentifier(from: SystemVoiceCatalog.installed())
      didResolveDefaultVoice = true
    }
    return resolvedDefaultVoiceId
  }

  private func selectedVoice() -> AVSpeechSynthesisVoice? {
    let stored = UserDefaults.standard.string(forKey: "speechVoiceId") ?? ""
    // An empty selection resolves to the best installed English voice rather than
    // leaving the voice nil — nil makes AVSpeech fall back to the device-language
    // compact voice, which ignores the user's choice and mispronounces English on
    // a non-English device. See SystemVoiceCatalog.
    let id = stored.isEmpty ? defaultVoiceId() : stored
    return id.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
  }

  /// Strips leading/trailing whitespace and parser prompt characters (`>`)
  /// from text before synthesis. AVSpeechSynthesizer would otherwise
  /// pronounce ">" as "greater than sign", which is just noise.
  nonisolated private static let promptCharacters = CharacterSet(charactersIn: ">")

  nonisolated private static func cleanForSpeech(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: promptCharacters)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func didFinishUtterance(_ cause: String) {
    if let next = pendingContinuations.first {
      pendingContinuations.removeFirst()
      next.resume()
    }
    if pendingContinuations.isEmpty {
      isSpeaking = false
    }
    DiagnosticsLog.ttsEvent(cause, pending: pendingContinuations.count, speaking: isSpeaking)
  }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      didFinishUtterance("didFinish")
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      didFinishUtterance("didCancel")
    }
  }
}
