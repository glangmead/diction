import Foundation

/// App-level owner of the single shared neural engine. Lives at the Bootstrap
/// level (`DictionApp`) and is injected via `.environment`, so the model can be
/// warmed while the user browses the library and the same warmed instance
/// carries into whichever game they open. Centralizes the neural-voice config
/// (the `useKokoro` flag and selected voice) so the library has one readiness
/// value to render.
@Observable @MainActor
final class VoiceWarmer {
  enum Readiness: Equatable {
    case systemVoice            // neural off → instant, no load
    case preparing
    case ready
    case unavailable(String)    // ANE missing etc.; playback falls back to system
  }

  let engine = KokoroSpeechEngine()

  /// Set when the library passes the live entitlement into `warmUpIfNeeded`.
  /// Warming and readiness are gated on it so a locked (or refunded) user never
  /// sees a stuck "preparing" banner for a model they can't hear.
  private var unlocked = false

  var readiness: Readiness {
    Self.resolveReadiness(useKokoro: useKokoro && unlocked, state: engine.state)
  }

  /// Pure mapping, unit-tested without a live engine.
  nonisolated static func resolveReadiness(useKokoro: Bool, state: KokoroSpeechEngine.State) -> Readiness {
    guard useKokoro else { return .systemVoice }
    switch state {
    case .idle, .preparing: return .preparing
    case .ready: return .ready
    case .unavailable(let reason): return .unavailable(reason)
    }
  }

  /// Begin loading the neural model + lexicon now (e.g. when the library
  /// appears) so opening a game is latency-free. No-op when the neural voice is
  /// off or not unlocked — the system voice needs no load. Idempotent.
  func warmUpIfNeeded(unlocked: Bool) {
    self.unlocked = unlocked
    guard useKokoro && unlocked else { return }
    let british = KokoroSpeechEngine.isBritish(voiceID: selectedVoiceID)
    Task {
      await engine.prepareIfNeeded()
      await engine.prewarmLexicon(british: british)
    }
  }

  /// Default off: neural narration is a paid feature.
  private var useKokoro: Bool {
    UserDefaults.standard.object(forKey: "useKokoro") as? Bool ?? false
  }

  private var selectedVoiceID: String {
    let id = UserDefaults.standard.string(forKey: "kokoroVoiceId") ?? ""
    return id.isEmpty ? "af_heart" : id
  }
}
