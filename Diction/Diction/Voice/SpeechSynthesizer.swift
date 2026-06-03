import Foundation
import AVFoundation

/// Speaks game output and command echoes. Echoes use a lower pitch so the
/// user can hear them as distinct from the game's voice.
@Observable
@MainActor
final class SpeechSynthesizer: NSObject {
  private(set) var isSpeaking = false

  /// True while the neural voice model is loading (cold start can take ~15 s on
  /// device). Lets the game UI show a loading affordance; always false when the
  /// neural path is off, since the system voice needs no load.
  var isPreparingVoice: Bool { useKokoro && kokoro.state == .preparing }

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

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speakCommandEcho(_ command: String) async {
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
  }

  /// Kick the Kokoro model load early (cold start ~2-3s) so the opening
  /// narration doesn't pay for it. Call from the game view's appear.
  func warmUpKokoro() {
    guard useKokoro else { return }
    Task { await kokoro.prepareIfNeeded() }
  }

  /// Adopt the app-level shared engine (warmed on the library by `VoiceWarmer`)
  /// so opening a game reuses the already-loaded model instead of starting a
  /// second cold load. Call before any narration.
  func useSharedEngine(_ engine: KokoroSpeechEngine) {
    kokoro = engine
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

  private func enqueue(_ utterance: AVSpeechUtterance) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      pendingContinuations.append(continuation)
      isSpeaking = true
      synthesizer.speak(utterance)
    }
  }

  private var speechRate: Float {
    let stored = UserDefaults.standard.float(forKey: "speechRate")
    return stored > 0 ? Float(stored) : AVSpeechUtteranceDefaultSpeechRate
  }

  /// Spike toggle (default on): use the neural voice when the model is present.
  private var useKokoro: Bool {
    UserDefaults.standard.object(forKey: "useKokoro") as? Bool ?? true
  }

  private var kokoroGameVoice: String {
    let id = UserDefaults.standard.string(forKey: "kokoroVoiceId") ?? ""
    let stored = id.isEmpty ? "af_heart" : id
    return DemoPolicy.effectiveKokoroVoice(stored, fullVersion: isFullVersion())
  }

  /// Kokoro speed from the shared Settings rate, so `faster` / `slower` and the
  /// rate slider track across both engines.
  private var kokoroSpeed: Float {
    KokoroSpeechEngine.speed(forStoredRate: speechRate)
  }

  private func selectedVoice() -> AVSpeechSynthesisVoice? {
    let id = UserDefaults.standard.string(forKey: "speechVoiceId") ?? ""
    return id.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: id)
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

  private func didFinishUtterance() {
    if let next = pendingContinuations.first {
      pendingContinuations.removeFirst()
      next.resume()
    }
    if pendingContinuations.isEmpty {
      isSpeaking = false
    }
  }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      didFinishUtterance()
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      didFinishUtterance()
    }
  }
}
