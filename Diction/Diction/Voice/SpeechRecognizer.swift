import Speech
import AVFoundation

/// Continuous speech recognition with echo-cancelled, always-live capture.
///
/// In continuous mode the microphone stays open even while the app's own
/// text-to-speech is playing: Apple's voice-processing I/O unit
/// (`setVoiceProcessingEnabled`) cancels the synthesizer's audio from the mic
/// input, so the recognizer hears the user rather than the narration. Each
/// utterance is finalized after ~1.2s of stable transcription and delivered via
/// `onUtterance`; the next capture cycle starts immediately, so listening is
/// continuous with no caller-driven suspend/resume.
@Observable
@MainActor
final class SpeechRecognizer {
  /// Live transcription text while listening.
  private(set) var transcription = ""

  /// True while a recognition cycle is capturing.
  private(set) var isListening = false

  private(set) var errorMessage: String?

  /// Called when a complete utterance is detected. Set before `startContinuous`.
  var onUtterance: ((String) -> Void)?

  private let recognizer: SFSpeechRecognizer?
  private var audioEngine: AVAudioEngine?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  private var inContinuous = false
  private var contextualStringsProvider: (@MainActor () -> [String])?

  private var silenceTask: Task<Void, Never>?
  private let silenceInterval: Duration = .milliseconds(1200)

  /// Schedules the next cycle after a backoff when the recognizer is thrashing
  /// (erroring before it can capture audio). Cancelled on stop.
  private var restartTask: Task<Void, Never>?
  /// Run of consecutive cold/empty cycles; drives the restart backoff so a
  /// failing recognizer can't busy-loop `beginCycle`. See `RecognitionRestartPolicy`.
  private var consecutiveFastFailures = 0
  private let clock = ContinuousClock()
  /// When the current cycle began, to measure its duration on end.
  private var cycleStart: ContinuousClock.Instant?

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

  /// Enter continuous mode: configure the session, enable voice processing,
  /// start the engine, and begin the first capture cycle. The provider is
  /// called fresh at the start of every cycle so biasing adapts to game state.
  func startContinuous(contextualStringsProvider: @MainActor @escaping () -> [String]) {
    guard !inContinuous else { return }
    inContinuous = true
    consecutiveFastFailures = 0
    self.contextualStringsProvider = contextualStringsProvider
    do {
      try startEngine()
      beginCycle()
    } catch {
      errorMessage = "Speech start failed: \(error)"
      inContinuous = false
    }
  }

  /// Leave continuous mode and release the engine and audio session.
  func stopContinuous() {
    inContinuous = false
    contextualStringsProvider = nil
    silenceTask?.cancel()
    restartTask?.cancel()
    consecutiveFastFailures = 0
    audioEngine?.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.finish()
    request = nil
    task = nil
    audioEngine?.stop()
    audioEngine = nil
    // Actually release the shared session (the method comment always claimed
    // this). Leaving it active meant a second game's fresh engine enabled voice
    // processing over a still-active session, and its input node came up with an
    // invalid (0 Hz / 0 ch) format — the crash on re-opening a game. Deactivating
    // lets the next `startEngine` re-initialise voice processing cleanly.
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    isListening = false
  }

  // MARK: - Engine + cycle lifecycle

  private func startEngine() throws {
    guard let recognizer, recognizer.isAvailable else {
      errorMessage = "Speech recognition not available"
      throw CocoaError(.featureUnsupported)
    }
    errorMessage = nil

    let session = AVAudioSession.sharedInstance()
    // Voice processing supplies echo cancellation; it needs a voice-oriented
    // mode, not `.measurement` (which strips the processing). VPIO cancels our
    // own TTS from the mic even though the synthesizer plays outside this engine.
    try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let engine = AVAudioEngine()
    let input = engine.inputNode
    // Enable echo cancellation BEFORE reading the input format (enabling it
    // changes the node's format).
    //
    // We deliberately do NOT set `voiceProcessingOtherAudioDuckingConfiguration`:
    // the device spike showed VPIO's *default* ducking lowers our narration when
    // the user speaks just enough for the recognizer to finalize the user's
    // command mid-narration. Setting `enableAdvancedDucking: true` (any level)
    // suppressed that ducking entirely, so the user's barge-in never finalized.
    try input.setVoiceProcessingEnabled(true)

    // NOTE: do NOT try to silence the `auou/vpio render err: -1` log spew by
    // connecting the input to `mainMixerNode` (even at `outputVolume = 0`).
    // Routing the mic into the VPIO output graph kills capture entirely — the
    // recognizer goes deaf (transcription frozen, no barge-in). The render
    // error is benign console noise from the unconnected duplex output bus;
    // capture and barge-in work fine despite it. Leave the output unconnected.
    engine.prepare()
    try engine.start()
    audioEngine = engine
  }

  /// Start one recognition cycle on the already-running engine. The tap
  /// captures a fresh `req` local (concurrency-safe on the audio thread);
  /// recycling per utterance keeps capture continuous without stopping VPIO.
  private func beginCycle() {
    guard let recognizer, let engine = audioEngine else { return }

    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    let cappedContext = Array((contextualStringsProvider?() ?? []).prefix(1000))
    req.contextualStrings = cappedContext
    req.taskHint = .search
    if recognizer.supportsOnDeviceRecognition {
      req.requiresOnDeviceRecognition = true
    }
    self.request = req

    let joined = cappedContext.joined(separator: ", ")
    let contextMsg = "[diction-dict] contextualStrings (\(cappedContext.count)): \(joined)\n"
    FileHandle.standardError.write(Data(contextMsg.utf8))

    let input = engine.inputNode
    input.removeTap(onBus: 0)
    let format = input.outputFormat(forBus: 0)
    // `installTap` aborts (IsFormatSampleRateAndChannelCountValid) if the input
    // format is degenerate — which is what voice processing reports when there's
    // no real mic input (notably the Simulator). Degrade to "no listening"
    // rather than crash; narration and typed input still work.
    guard format.sampleRate > 0, format.channelCount > 0 else {
      let desc = "\(format.sampleRate)Hz/\(format.channelCount)ch"
      FileHandle.standardError.write(Data("[diction-rec] invalid mic format \(desc); listening off\n".utf8))
      errorMessage = "Microphone input is unavailable on this device."
      isListening = false
      return
    }
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      req.append(buffer)
    }

    transcription = ""
    isListening = true
    cycleStart = clock.now

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

  /// Cancels any in-flight silence timer and starts a new one. When it fires
  /// uncancelled, the user is considered done talking.
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
    request?.endAudio()
  }

  /// End one cycle and immediately start the next while the engine keeps
  /// running, so the mic is live continuously — including during narration.
  private func endCycle(emitFinal: Bool) {
    silenceTask?.cancel()
    let final = transcription
    audioEngine?.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.finish()
    request = nil
    task = nil

    if emitFinal,
       !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      onUtterance?(final)
    }

    guard inContinuous else {
      isListening = false
      return
    }

    // Re-arm the next cycle, but throttle when the recognizer is thrashing —
    // erroring before it can capture audio (cold on-device model right after
    // engine start, or a Simulator with no on-device model). Restarting such a
    // cold/empty cycle instantly busy-loops the request hundreds of times a
    // second and destroys the user's first utterance; a duration-aware backoff
    // stops that while keeping healthy listening instant. See RecognitionRestartPolicy.
    let duration = cycleStart?.duration(to: clock.now) ?? .seconds(1)
    let producedText = !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if RecognitionRestartPolicy.isFastFailure(producedText: producedText, duration: duration) {
      consecutiveFastFailures += 1
    } else {
      consecutiveFastFailures = 0
    }

    let delay = RecognitionRestartPolicy.restartDelay(consecutiveFastFailures: consecutiveFastFailures)
    if delay == .zero {
      beginCycle()
    } else {
      restartTask?.cancel()
      restartTask = Task { [weak self] in
        try? await Task.sleep(for: delay)
        if Task.isCancelled { return }
        await MainActor.run {
          guard let self, self.inContinuous else { return }
          self.beginCycle()
        }
      }
    }
  }
}
