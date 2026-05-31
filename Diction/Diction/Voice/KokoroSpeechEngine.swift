import Foundation
import AVFoundation
import FluidAudio

/// Throwaway spike: neural TTS via FluidAudio's Kokoro 82M (`KokoroAneManager`,
/// CoreML on the Apple Neural Engine), played through `AVAudioPlayer`.
///
/// `AVAudioPlayer` feeds the system output mix the same way `AVSpeechSynthesizer`
/// does — which already coexists with (and is echo-cancelled by) the recognizer's
/// voice-processing engine. It deliberately does NOT touch the recognizer's
/// engine: an earlier attempt to render through that engine broke the mic input.
///
/// Models load read-only from the bundled `KokoroModels.bundle`; only the tiny
/// shared G2P assets are copied into the writable cache, because the SDK
/// hardcodes the English G2P path to its default cache directory and ignores the
/// `directory:` override for that one asset.
@Observable
@MainActor
final class KokoroSpeechEngine: NSObject {

  enum State: Equatable {
    case idle
    case preparing
    case ready
    case unavailable(String)
  }

  private(set) var state: State = .idle
  var isReady: Bool { state == .ready }

  /// Human-readable status for the Settings picker.
  var statusDescription: String {
    switch state {
    case .idle: return "Not loaded"
    case .preparing: return "Loading…"
    case .ready: return "Ready"
    case .unavailable(let reason): return "Unavailable — \(reason)"
    }
  }

  /// Set true for the Settings audition instance (no recognizer running) so it
  /// configures the audio session itself. In a game the recognizer owns the
  /// session, so the in-game instance leaves it alone (like `AVSpeechSynthesizer`).
  var managesSession = false

  /// The English voice packs bundled in `KokoroModels.bundle`, in display order
  /// (US female, US male, UK female, UK male). Names map to `<id>.bin` files.
  static let bundledEnglishVoiceIDs: [String] = [
    "af_heart", "af_bella", "af_nicole", "af_sarah", "af_sky", "af_aoede",
    "af_alloy", "af_jessica", "af_kore", "af_nova", "af_river", "af",
    "am_michael", "am_onyx", "am_adam", "am_echo", "am_eric", "am_fenrir",
    "am_liam", "am_puck", "am_santa",
    "bf_emma", "bf_alice", "bf_isabella", "bf_lily",
    "bm_george", "bm_daniel", "bm_fable", "bm_lewis"
  ]

  /// "af_heart" → "Heart"; bare "af" → "Default".
  static func displayName(for voiceID: String) -> String {
    guard let under = voiceID.firstIndex(of: "_") else { return "Default" }
    let stem = String(voiceID[voiceID.index(after: under)...])
    return stem.prefix(1).uppercased() + stem.dropFirst()
  }

  /// Map the Settings speech-rate slider (AVSpeech units, default
  /// `AVSpeechUtteranceDefaultSpeechRate`) onto Kokoro's speed multiplier
  /// (1.0 = normal), clamped so both engines track the same control.
  static func speed(forStoredRate rate: Float) -> Float {
    min(max(rate / AVSpeechUtteranceDefaultSpeechRate, 0.5), 2.0)
  }

  /// "af_heart" → "US · Female", "bm_george" → "UK · Male".
  static func accentLabel(for voiceID: String) -> String {
    let region = voiceID.hasPrefix("a") ? "US" : voiceID.hasPrefix("b") ? "UK" : "Other"
    let gender = voiceID.dropFirst().hasPrefix("f")
      ? "Female" : voiceID.dropFirst().hasPrefix("m") ? "Male" : ""
    return gender.isEmpty ? region : "\(region) · \(gender)"
  }

  private var manager: KokoroAneManager?
  private var audioPlayer: AVAudioPlayer?

  /// Lexicon-first phonemizer (misaki lexicon + neural fallback, clitic-aware).
  /// When present we feed its IPA to `synthesizeFromPhonemes`, bypassing the ANE
  /// path's context-free per-word G2P. Nil → fall back to the built-in G2P.
  private var phonemizer: KokoroPhonemizer?

  /// The in-flight model load, so concurrent callers (warm-up + the opening
  /// narration) await the *same* preparation instead of the narration bailing to
  /// the fallback voice because the model is still loading.
  private var prepareTask: Task<Void, Never>?

  /// Set by `stop()`; checked between chunks so a narration pass halts at the
  /// next chunk boundary rather than after the whole text.
  private var stopped = false

  /// The in-flight `play()` await, resumed exactly once — when the clip finishes
  /// or `stop()` cuts it short. The nil guard makes both paths safe.
  private var playbackContinuation: CheckedContinuation<Void, Never>?

  /// Bundle root containing `kokoro-82m-coreml/ANE/...` (the 7-stage chain +
  /// voices) and `kokoro/...` (the shared G2P assets).
  private static var bundledModelsRoot: URL? {
    Bundle.main.url(forResource: "KokoroModels", withExtension: "bundle")
  }

  override init() {
    super.init()
  }

  // MARK: - Lifecycle

  /// Seed G2P into the cache, load the ANE chain from the bundle, warm the
  /// default voice. Idempotent, and — crucially — **awaits an in-flight load**
  /// so a narration pass that fires during warm-up waits for the model rather
  /// than falling back to the system voice.
  func prepareIfNeeded() async {
    switch state {
    case .ready, .unavailable:
      return
    case .idle, .preparing:
      break
    }
    if prepareTask == nil {
      state = .preparing
      prepareTask = Task { [weak self] in await self?.loadModel() }
    }
    await prepareTask?.value
  }

  private func loadModel() async {
    guard let root = Self.bundledModelsRoot else {
      state = .unavailable("KokoroModels.bundle missing from app bundle")
      return
    }
    do {
      // `ensureModels` appends "kokoro-82m-coreml/ANE" to this directory.
      try Self.seedG2PCacheIfNeeded(fromBundleRoot: root)
      let mgr = KokoroAneManager(variant: .english, directory: root)
      try await mgr.initialize()
      manager = mgr
      // Built after the manager so G2PModel (the phonemizer's OOV fallback) is
      // loaded. Best-effort: nil leaves the built-in per-word G2P in place.
      phonemizer = await KokoroPhonemizer.load(bundleRoot: root)
      state = .ready
    } catch {
      // Simulator (no ANE), missing model, or G2P seed failure → caller falls
      // back to AVSpeechSynthesizer for the session.
      manager = nil
      state = .unavailable(error.localizedDescription)
      print("[kokoro] unavailable: \(error)")
    }
  }

  // MARK: - Speech

  /// Synthesize and play `text` in `voice`, sentence-chunked to respect the
  /// 510-phoneme cap and to start audio sooner. Returns when playback finishes
  /// or `stop()` is called.
  func speak(_ text: String, voice: String, speed: Float) async {
    guard let manager else { return }
    stopped = false
    for chunk in Self.chunk(text) {
      if stopped { return }
      do {
        let result: KokoroAneSynthesisResult
        if let phonemizer {
          // bf_/bm_ are the British voice packs; everything else is US.
          let british = voice.hasPrefix("bf_") || voice.hasPrefix("bm_")
          let ipa = try await phonemizer.phonemize(chunk, british: british)
          print("[kokoro] speed=\(speed) IPA: \(chunk.prefix(24))… -> \(ipa.prefix(80))")
          result = try await manager.synthesizeFromPhonemesDetailed(ipa, voice: voice, speed: speed)
        } else {
          result = try await manager.synthesizeDetailed(text: chunk, voice: voice, speed: speed)
        }
        if stopped { return }
        // Each clip is one sentence, so the model's leading + trailing silence
        // pads (~290 ms + ~490 ms) would otherwise stack into a ~780 ms gap at
        // every sentence boundary. Trim each clip to a short controlled tail.
        let trimmed = KokoroPCM.trimSilence(result.samples, sampleRate: result.sampleRate)
        let wav = KokoroPCM.wavData(trimmed, sampleRate: result.sampleRate)
        ensureSessionForPlayback()
        await play(wav)
      } catch {
        // Skip the failed chunk; do not kill the whole pass.
        print("[kokoro] chunk failed (\(chunk.prefix(40))…): \(error)")
      }
    }
  }

  func stop() {
    stopped = true
    audioPlayer?.stop()
    finishPlayback()
  }

  // MARK: - Playback

  private func play(_ wav: Data) async {
    let player: AVAudioPlayer
    do {
      player = try AVAudioPlayer(data: wav)
    } catch {
      print("[kokoro] AVAudioPlayer init failed: \(error)")
      return
    }
    player.delegate = self
    audioPlayer = player
    player.prepareToPlay()
    if stopped { return }

    // Store the continuation before `play()` so an instant-finish callback can't
    // race ahead of it.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      playbackContinuation = continuation
      player.play()
    }
  }

  /// Resume the pending `play()` await exactly once. Idempotent via the nil
  /// guard, so the finish callback and `stop()` can both call it.
  private func finishPlayback() {
    guard let continuation = playbackContinuation else { return }
    playbackContinuation = nil
    continuation.resume()
  }

  /// Audition (no recognizer) configures the session for playback. In a game the
  /// recognizer already owns an active `.playAndRecord` session, so leave it.
  private func ensureSessionForPlayback() {
    guard managesSession else { return }
    let session = AVAudioSession.sharedInstance()
    if session.category != .playback && session.category != .playAndRecord {
      try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
    }
    try? session.setActive(true)
  }

  // MARK: - Model seeding

  /// Copy the shared G2P assets (`G2PEncoder.mlmodelc`, `G2PDecoder.mlmodelc`,
  /// `g2p_vocab.json`) from the bundle into `<caches>/fluidaudio/Models/kokoro/`
  /// if absent. The KokoroAne English path reads G2P only from that fixed cache
  /// location, so pointing `directory:` at the bundle is not enough for it.
  private static func seedG2PCacheIfNeeded(fromBundleRoot root: URL) throws {
    let fileManager = FileManager.default
    guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      throw CocoaError(.fileNoSuchFile)
    }
    let dest = caches.appendingPathComponent("fluidaudio/Models/kokoro", isDirectory: true)
    let src = root.appendingPathComponent("kokoro", isDirectory: true)
    let required = ["G2PEncoder.mlmodelc", "G2PDecoder.mlmodelc", "g2p_vocab.json"]

    let allPresent = required.allSatisfy {
      fileManager.fileExists(atPath: dest.appendingPathComponent($0).path)
    }
    if allPresent { return }

    try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
    for name in required {
      let from = src.appendingPathComponent(name)
      let target = dest.appendingPathComponent(name)
      if fileManager.fileExists(atPath: target.path) { continue }
      try fileManager.copyItem(at: from, to: target)
    }
  }

  // MARK: - Chunking

  /// Split text into sentence-ish chunks, hard-wrapping any piece longer than
  /// `maxChars` at a word boundary so the IPA stays under the 510-phoneme cap.
  static func chunk(_ text: String, maxChars: Int = 240) -> [String] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    var sentences: [String] = []
    var current = ""
    for char in trimmed {
      current.append(char)
      if char == "." || char == "!" || char == "?" || char == "\n" {
        let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !piece.isEmpty { sentences.append(piece) }
        current = ""
      }
    }
    let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !tail.isEmpty { sentences.append(tail) }

    var result: [String] = []
    for sentence in sentences where !sentence.isEmpty {
      if sentence.count <= maxChars {
        result.append(sentence)
      } else {
        result.append(contentsOf: wrap(sentence, maxChars: maxChars))
      }
    }
    return result
  }

  private static func wrap(_ sentence: String, maxChars: Int) -> [String] {
    var pieces: [String] = []
    var line = ""
    for word in sentence.split(separator: " ") {
      if line.isEmpty {
        line = String(word)
      } else if line.count + 1 + word.count <= maxChars {
        line += " " + word
      } else {
        pieces.append(line)
        line = String(word)
      }
    }
    if !line.isEmpty { pieces.append(line) }
    return pieces
  }
}

extension KokoroSpeechEngine: AVAudioPlayerDelegate {
  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in self.finishPlayback() }
  }
}
