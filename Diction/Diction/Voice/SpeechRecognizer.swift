import Speech
import AVFoundation

/// Continuous speech recognition with silence-based end-of-utterance
/// detection. After ~1.2s of stable partial transcription, the current
/// utterance is finalized and `onUtterance` is invoked with the recognized
/// text; capture stops until the caller calls `setExternallySuspended(false)`
/// (typically after TTS playback finishes).
///
/// Two independent suspension axes:
/// - `setUserMuted(_:)` — user tapped the mute button.
/// - `setExternallySuspended(_:)` — caller is busy (e.g. TTS speaking).
///
/// Audio capture runs only while continuous mode is on AND neither axis
/// is asserted.
@Observable
@MainActor
final class SpeechRecognizer {
  /// Live updated transcription text while listening.
  private(set) var transcription = ""

  /// True while the audio engine is capturing (a single recognition cycle).
  private(set) var isListening = false

  /// User-controlled mute. Visible to the UI so the mic button can reflect it.
  private(set) var isUserMuted = false

  private(set) var errorMessage: String?

  /// Called when continuous mode detects a complete utterance.
  /// Set before invoking `startContinuous`. Runs on the MainActor.
  var onUtterance: ((String) -> Void)?

  private let recognizer: SFSpeechRecognizer?
  private var audioEngine: AVAudioEngine?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  private var inContinuous = false
  private var isExternallySuspended = false
  private var contextualStrings: [String] = []

  private var silenceTask: Task<Void, Never>?
  private let silenceInterval: Duration = .milliseconds(1200)

  init(locale: Locale = Locale(identifier: "en-US")) {
    recognizer = SFSpeechRecognizer(locale: locale)
  }

  // MARK: - Authorization

  func requestAuthorization() async -> Bool {
    let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
    guard speech else { return false }

    let mic = await AVAudioApplication.requestRecordPermission()
    return mic
  }

  // MARK: - Continuous mode

  /// Enter continuous mode. Capture starts immediately unless suspended.
  func startContinuous(contextualStrings: [String]) {
    inContinuous = true
    self.contextualStrings = contextualStrings
    reconcile()
  }

  /// Leave continuous mode. Releases the audio session and clears the
  /// transient external-suspension flag so a subsequent `startContinuous`
  /// gets a clean slate (user-mute is preserved as a sticky preference).
  func stopContinuous() {
    inContinuous = false
    isExternallySuspended = false
    silenceTask?.cancel()
    stopCaptureInternal()
  }

  func setUserMuted(_ muted: Bool) {
    isUserMuted = muted
    reconcile()
  }

  /// Used by the caller (e.g., GameView) to pause capture while TTS plays.
  func setExternallySuspended(_ suspended: Bool) {
    isExternallySuspended = suspended
    reconcile()
  }

  // MARK: - State machine

  private var canCapture: Bool {
    inContinuous && !isUserMuted && !isExternallySuspended
  }

  private func reconcile() {
    if canCapture && !isListening {
      do {
        try startCaptureCycle()
      } catch {
        errorMessage = "Speech start failed: \(error)"
      }
    } else if !canCapture && isListening {
      silenceTask?.cancel()
      stopCaptureInternal()
    }
  }

  private func startCaptureCycle() throws {
    guard let recognizer, recognizer.isAvailable else {
      errorMessage = "Speech recognition not available"
      return
    }
    errorMessage = nil

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .measurement,
      options: [.duckOthers, .defaultToSpeaker]
    )
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    // Apple's docs don't publish a hard limit, but ~1000 strings is the
    // commonly cited practical ceiling. Above 200 the per-string weight
    // is reduced, but inclusion still helps the recognizer prefer these
    // words over similar-sounding common-vocabulary alternatives.
    let cappedContext = Array(contextualStrings.prefix(1000))
    req.contextualStrings = cappedContext
    // Tell the recognizer to expect short, command-style utterances. This
    // shifts its language model away from free-dictation priors that prefer
    // common English over IF-specific monosyllables like "west" vs "wet".
    req.taskHint = .search
    if recognizer.supportsOnDeviceRecognition {
      req.requiresOnDeviceRecognition = true
    }
    self.request = req

    let joined = cappedContext.joined(separator: ", ")
    let contextMsg = "[diction-dict] contextualStrings (\(cappedContext.count)): \(joined)\n"
    FileHandle.standardError.write(Data(contextMsg.utf8))

    let engine = AVAudioEngine()
    self.audioEngine = engine

    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      req.append(buffer)
    }

    engine.prepare()
    try engine.start()

    transcription = ""
    isListening = true

    task = recognizer.recognitionTask(with: req) { [weak self] result, error in
      guard let self else { return }
      Task { @MainActor in
        self.handleRecognitionEvent(result: result, error: error)
      }
    }
  }

  private func handleRecognitionEvent(
    result: SFSpeechRecognitionResult?,
    error: Error?
  ) {
    if let result {
      let new = result.bestTranscription.formattedString
      if new != transcription {
        transcription = new
        scheduleSilenceCheck()
      }
      if result.isFinal {
        endCycle(emitFinal: true)
        return
      }
    }
    if error != nil {
      endCycle(emitFinal: false)
    }
  }

  /// Cancels any in-flight silence timer and starts a new one. When it
  /// fires uncancelled, the user is considered done talking.
  private func scheduleSilenceCheck() {
    silenceTask?.cancel()
    let interval = silenceInterval
    silenceTask = Task { [weak self] in
      try? await Task.sleep(for: interval)
      if Task.isCancelled { return }
      await MainActor.run {
        self?.silenceFired()
      }
    }
  }

  private func silenceFired() {
    guard isListening,
          !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    // Asks the recognizer to deliver isFinal=true; handleRecognitionEvent
    // will route to endCycle.
    request?.endAudio()
  }

  private func endCycle(emitFinal: Bool) {
    silenceTask?.cancel()
    let final = transcription
    stopCaptureInternal()

    if emitFinal,
       !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      onUtterance?(final)
    }
    // Capture does not auto-restart here. The caller is expected to
    // process the utterance, play TTS, and toggle externally-suspended
    // to bring the next cycle up via `reconcile()`.
  }

  private func stopCaptureInternal() {
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.finish()
    audioEngine = nil
    request = nil
    task = nil
    isListening = false
  }
}
