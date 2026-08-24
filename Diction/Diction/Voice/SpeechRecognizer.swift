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

  /// Called when a complete utterance is detected, carrying per-word alternatives
  /// for post-recognition recovery. Set before `startContinuous`.
  var onUtterance: ((RecognizedUtterance) -> Void)?

  private let recognizer: SFSpeechRecognizer?
  /// The shared session (injectable so the stop path is testable).
  private let session: any AudioSessionControlling
  private var audioEngine: AVAudioEngine?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  /// The most recent best transcription, kept so a finalized cycle can deliver its
  /// segments' alternatives (the lever for acronym recovery), not just a string.
  private var latestTranscription: SFTranscription?

  private var inContinuous = false
  private var contextualStringsProvider: (@MainActor () -> [String])?

  /// True from `startContinuous` until `stopContinuous` (or a failed start): the
  /// window in which this recognizer owns the shared audio session as
  /// `.playAndRecord`. Narrators consult this — never the session's category —
  /// before touching the session. See `NarrationSessionConfig.shouldApply`.
  var ownsAudioSession: Bool { inContinuous }

  private var silenceTask: Task<Void, Never>?
  private let silenceInterval: Duration = .milliseconds(1200)
  /// Set when the silence timer fires and we call `endAudio()` — i.e. the user
  /// finished and the transcription is a complete, stable utterance. Lets a cycle
  /// that then ends on a transient error (common on-device) still deliver its
  /// text instead of dropping it. Reset per cycle. See `RecognitionFinalizationPolicy`.
  private var endpointed = false

  /// Schedules the next cycle after a backoff when the recognizer is thrashing
  /// (erroring before it can capture audio). Cancelled on stop.
  private var restartTask: Task<Void, Never>?
  /// Run of consecutive cold/empty cycles; drives the restart backoff so a
  /// failing recognizer can't busy-loop `beginCycle`. See `RecognitionRestartPolicy`.
  private var consecutiveFastFailures = 0
  private let clock = ContinuousClock()
  /// When the current cycle began, to measure its duration on end.
  private var cycleStart: ContinuousClock.Instant?

  /// The audio-session configuration applied by `startEngine` — the routing policy
  /// (input choice + live output context) from `AudioRouteController`, captured per
  /// continuous session. Replaced on each `startContinuous`.
  private var sessionConfig = ListeningSessionConfig.default

  init(
    locale: Locale = Locale(identifier: "en-US"),
    session: any AudioSessionControlling = AVAudioSession.sharedInstance()
  ) {
    recognizer = SFSpeechRecognizer(locale: locale)
    self.session = session
  }

  // MARK: - Authorization

  func requestAuthorization() async -> Bool {
    let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      // `@Sendable`: Speech calls this on an arbitrary queue; an implicit
      // `@MainActor` closure (the app's default isolation) traps there under Swift 6.
      SFSpeechRecognizer.requestAuthorization { @Sendable status in
        continuation.resume(returning: status == .authorized)
      }
    }
    guard speech else { return false }
    let mic = await AVAudioApplication.requestRecordPermission()
    return mic
  }

  // MARK: - Continuous mode

  /// Enter continuous mode: configure the session per `config`, enable voice
  /// processing (unless the config opts out), start the engine, and begin the
  /// first capture cycle. The provider is called fresh at the start of every cycle
  /// so biasing adapts to game state.
  func startContinuous(
    config: ListeningSessionConfig,
    contextualStringsProvider: @MainActor @escaping () -> [String]
  ) {
    guard !inContinuous else { return }
    inContinuous = true
    consecutiveFastFailures = 0
    sessionConfig = config
    self.contextualStringsProvider = contextualStringsProvider
    do {
      try startEngine()
      beginCycle()
    } catch {
      errorMessage = "Speech start failed: \(error)"
      inContinuous = false
      // `startEngine` may have put the session into `.playAndRecord` before it
      // threw; hand it back so narration doesn't inherit a half-configured session.
      restoreNarrationSession()
    }
  }

  /// Leave continuous mode: release the engine and hand the audio session back
  /// to narration.
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
    restoreNarrationSession()
    isListening = false
  }

  /// Hand the still-active session back in the narration configuration —
  /// `startEngine` put it into `.playAndRecord`, and only a live recognizer may
  /// own that (see `NarrationSessionConfig`).
  ///
  /// Deliberately does NOT `setActive(false)`: deactivating under a playing
  /// narrator wedges a neural-voice `AVAudioPlayer` (its finish callback never
  /// comes), and the post-VPIO output attenuation is cleared only by a category
  /// change on an *active* session (impl #02 has the device trace). The
  /// deactivation used to guard against a 0 Hz / 0 ch input format on the next
  /// engine; the category flip reconfigures the I/O instead, and `beginCycle`
  /// degrades rather than crashes if that ever recurs. A route change restarts
  /// the recognizer, so the category flips twice there — one extra notification.
  private func restoreNarrationSession() {
    try? ListeningSessionConfig.restoredOnStop.apply(to: session)
  }

  // MARK: - Engine + cycle lifecycle

  private func startEngine() throws {
    guard let recognizer, recognizer.isAvailable else {
      errorMessage = "Speech recognition not available"
      throw CocoaError(.featureUnsupported)
    }
    errorMessage = nil

    // Routing policy comes from `AudioRouteController` (input choice + live output
    // context) rather than a fixed `.defaultToSpeaker`, which used to force the
    // built-in speaker and kick narration off connected AirPods the moment the mic
    // opened. Voice processing still wants a voice-oriented mode (`.default`, not
    // `.measurement`); the policy decides the Bluetooth options and the preferred input.
    try session.setCategory(
      ListeningSessionConfig.category, mode: sessionConfig.mode, options: sessionConfig.options)
    try session.setActive(true, options: .notifyOthersOnDeactivation)
    if let uid = sessionConfig.preferredInputUID,
       let port = session.availableInputs?.first(where: { $0.uid == uid }) {
      try? session.setPreferredInput(port)
    }

    let engine = AVAudioEngine()
    let input = engine.inputNode
    // Enable echo cancellation BEFORE reading the input format (enabling it
    // changes the node's format). Skipped in the split-device case (Bluetooth A2DP
    // output + built-in-mic capture) the policy flags: VPIO would force a call
    // route and there's no real echo path to cancel (narration is in the user's ears).
    //
    // We deliberately do NOT set `voiceProcessingOtherAudioDuckingConfiguration`:
    // the device spike showed VPIO's *default* ducking lowers our narration when
    // the user speaks just enough for the recognizer to finalize the user's
    // command mid-narration. Setting `enableAdvancedDucking: true` (any level)
    // suppressed that ducking entirely, so the user's barge-in never finalized.
    if sessionConfig.enableVoiceProcessing {
      try input.setVoiceProcessingEnabled(true)
    }

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

    // Debug landmark: per-cycle dump of the contextual-strings bias list. Left
    // commented because it prints every cycle and buries the [diction-rec] trace;
    // uncomment to inspect biasing.
    // let joined = cappedContext.joined(separator: ", ")
    // let contextMsg = "[diction-dict] contextualStrings (\(cappedContext.count)): \(joined)\n"
    // FileHandle.standardError.write(Data(contextMsg.utf8))

    let input = engine.inputNode
    input.removeTap(onBus: 0)
    let format = input.outputFormat(forBus: 0)
    // `installTap` aborts (IsFormatSampleRateAndChannelCountValid) if the input
    // format is degenerate — which is what voice processing reports when there's
    // no real mic input (notably the Simulator). Degrade to "no listening"
    // rather than crash; narration and typed input still work.
    guard format.sampleRate > 0, format.channelCount > 0 else {
      let desc = "\(format.sampleRate)Hz/\(format.channelCount)ch"
      DiagnosticsLog.micFormatError(desc)
      errorMessage = "Microphone input is unavailable on this device."
      isListening = false
      return
    }
    // The tap runs on the audio render thread, so the block must be `@Sendable`
    // (same trap as above). Appending from that thread is the API's designed use.
    nonisolated(unsafe) let request = req
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
      request.append(buffer)
    }

    transcription = ""
    endpointed = false
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
      latestTranscription = result.bestTranscription
      let new = result.bestTranscription.formattedString
      if new != transcription {
        transcription = new
        scheduleSilenceCheck()
      }
      if result.isFinal {
        endCycle(terminus: .finalResult)
        return
      }
    }
    if let error {
      endCycle(terminus: .failed(error))
    }
  }

  /// How a capture cycle ended — drives both the delivery decision and the trace.
  private enum Terminus {
    case finalResult
    case failed(Error)
  }

  /// Trace every finalization that carried text (or reached a final result), so a
  /// dropped utterance is visible whichever branch it took: a transient error, or
  /// an empty/short final result that silently delivers nothing. Always-on (a
  /// final result at `.notice`, an error at `.error`) so it survives in `OSLogStore`
  /// for the in-app diagnostics export. Idle no-speech error cycles (no text, not
  /// final) are skipped so the trace isn't drowned. See `DiagnosticsLog`.
  private func logCycleEnd(terminus: Terminus, isFinal: Bool, hasText: Bool, text: String, deliver: Bool) {
    guard hasText || isFinal else { return }
    switch terminus {
    case .finalResult:
      DiagnosticsLog.cycleEnd(
        cause: "final", endpointed: endpointed, delivered: deliver, command: text)
    case .failed(let error):
      let nsError = error as NSError
      DiagnosticsLog.cycleEndError(
        cause: "error \(nsError.domain) \(nsError.code)",
        endpointed: endpointed, delivered: deliver, command: text)
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
    // The user has gone quiet on a non-empty transcription: this is a complete
    // utterance. Mark it so a cycle that ends on a transient error rather than a
    // final result still delivers it.
    endpointed = true
    request?.endAudio()
  }

  /// End one cycle and immediately start the next while the engine keeps
  /// running, so the mic is live continuously — including during narration.
  private func endCycle(terminus: Terminus) {
    silenceTask?.cancel()
    let final = transcription
    let utterance = latestTranscription.map(Self.utterance(from:)) ?? .plain(final)
    audioEngine?.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.finish()
    request = nil
    task = nil
    latestTranscription = nil

    let isFinal: Bool
    if case .finalResult = terminus { isFinal = true } else { isFinal = false }
    let hasText = !utterance.best.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let deliver = RecognitionFinalizationPolicy.shouldDeliver(
      isFinal: isFinal, endpointed: endpointed, hasText: hasText)
    logCycleEnd(terminus: terminus, isFinal: isFinal, hasText: hasText, text: utterance.best, deliver: deliver)
    if deliver {
      onUtterance?(utterance)
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

  /// Build a `RecognizedUtterance` from a transcription's segments, carrying each
  /// word's `alternativeSubstrings` for post-recognition recovery.
  private static func utterance(from transcription: SFTranscription) -> RecognizedUtterance {
    RecognizedUtterance(words: transcription.segments.map { segment in
      RecognizedUtterance.Word(
        best: segment.substring,
        alternatives: [segment.substring] + segment.alternativeSubstrings)
    })
  }
}
