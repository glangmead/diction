import Foundation
import AVFoundation

// swiftlint:disable file_length
// Pitch for the exception: this type is the single cohesive owner of the voice
// lifecycle (two axes + permission handshake), input dispatch/classification,
// narration, and the readout-overlay state. Those paths mutate the same private
// state — `synthesizer`, `lastNarratedEntries`, `activeReadout`/`readoutToken` —
// so moving handlers to an extension in another file would force widening that
// access, the same trade-off `InterpreterSession` documents and rejects. The
// per-command readback LOGIC already lives in separate pure helpers
// (`VoiceCommandCatalog`, `WindowInventory`, `InputHistory`, `KeywordScanner`);
// what remains here is thin glue. ~30 lines over; prefer the exception over
// scattering coupled state. The same reasoning covers the `type_body_length`
// disable on the declaration below.

/// Owns the voice lifecycle and orchestrates the mic, the synthesizer,
/// and the interpreter session. The View layer interacts with the
/// coordinator rather than the recognizer / synthesizer directly.
///
/// Two independent axes, both default-on:
/// - `isListening` — whether the app hears the user (mic / input)
/// - `isSpeaking` — whether the app narrates responses (TTS / output)
///
/// Responsibilities:
/// - The two axes + Speech / mic permission handshake
/// - Dispatching every input (typed or spoken) to either the game or to
///   a coordinator-addressed command ("game, reread")
/// - Tracking what was last narrated so commands like "reread" have
///   something to repeat
/// - Refusing to narrate state-reset responses (RESTORE / RESTART)
/// - One-shot opening narration the first time narration is active
@Observable
@MainActor
// swiftlint:disable:next type_body_length
final class VoiceCoordinator {
  // MARK: - View-observable state

  /// Input axis — is the app listening to the user. Off until someone with
  /// "Play using my voice" on opens a game where voice commands are allowed (or
  /// taps the mic there). `setListening` refuses whenever the game's gate says
  /// no, so it never starts for a free user outside a bundled game.
  private(set) var isListening = false
  /// Output axis — does the app speak. Toggling off stops the current sentence.
  /// Off and immutable in the Simulator, where TTS is unavailable (it screeches);
  /// see `SpeechSynthesizer.isAvailable`.
  private(set) var isSpeaking = !SpeechSynthesizer.isSimulator

  /// The readout currently shown in the overlay (the answer to `help`, `windows`,
  /// `history`, or `keywords`), or nil when none is up. The view reads this in
  /// `body`; `present(_:)` sets it and auto-dismisses it.
  private(set) var activeReadout: VoiceReadout?

  // MARK: - Owned services

  let recognizer = SpeechRecognizer()
  let synthesizer = SpeechSynthesizer()
  /// User-controllable mic input + output routing, and the source of the
  /// recognizer's session config. A device or input change reconfigures a live
  /// recognizer via `onConfigChange` → `reconfigureListeningIfNeeded`.
  let audioRoute = AudioRouteController()

  init() {
    audioRoute.onConfigChange = { [weak self] in
      self?.reconfigureListeningIfNeeded()
    }
  }

  // MARK: - Wake word

  /// The prefix marking an utterance as addressed to the app rather than the
  /// game. User-configurable in Settings; empty falls back to "game".
  var wakeWord: String {
    Self.normalizedWakeWord(UserDefaults.standard.string(forKey: "wakeWord"))
  }

  // MARK: - Connection to the game

  /// Weak: the View owns the session lifecycle.
  weak var session: InterpreterSession?

  func attach(session: InterpreterSession) {
    self.session = session
    // A new session is a new (or reset) game — narrate its opening afresh.
    hasNarratedOpening = false
    lastNarratedEntries = []
  }

  /// Route narration through the app-level shared neural engine warmed by
  /// `VoiceWarmer`, so the model loaded on the library carries into the game.
  func useSharedVoice(_ warmer: VoiceWarmer) {
    synthesizer.useSharedEngine(warmer.engine)
  }

  /// The live full-version entitlement, forwarded to the synthesizer so a
  /// free/refunded user never narrates with a locked neural voice. Listening is
  /// gated separately by `voiceCommandsAllowed`, which also admits a bundled game.
  private var isFullVersion: @MainActor () -> Bool = { false }

  /// Wire the app-level store's entitlement in. Weak so the coordinator doesn't
  /// retain the store.
  func useEntitlement(_ store: StoreManager) {
    isFullVersion = { [weak store] in store?.isFullVersion ?? false }
    synthesizer.isFullVersion = isFullVersion
  }

  /// Whether voice commands may run in the current game: purchased, or a
  /// bundled game where they are free to try (`DemoPolicy.voiceCommandsAllowed`).
  /// Closed until the game installs its gate, so a coordinator with no game
  /// never listens.
  private var voiceCommandsAllowed: @MainActor () -> Bool = { false }

  /// Install the game's voice-command gate. The game is the only place that
  /// knows the story's source, so it decides; this is the single choke point
  /// (`setListening`) that applies the decision.
  func useVoiceCommandGate(_ allowed: @escaping @MainActor () -> Bool) {
    voiceCommandsAllowed = allowed
  }

  /// The resolved speech profile (global). The TTS slice is forwarded to the
  /// synthesizer; the ASR slice is read here (contextual biasing, post-recognition
  /// recovery/corrections).
  private(set) var speechProfile = SpeechProfile.empty

  func useSpeechProfile(_ profile: SpeechProfile) {
    speechProfile = profile
    synthesizer.applyTTSInterventions(profile.tts)
  }

  /// Recover + correct a recognized utterance against the parser dictionary ∪
  /// profile vocabulary, per the ASR interventions. The recovery swaps a word the
  /// parser doesn't know (Apple's "POF") for an alternative it does ("PEOF"); the
  /// corrections force the rest. Voice path only — typed input bypasses this.
  private func postProcess(_ utterance: RecognizedUtterance) -> String {
    var known = Set(speechProfile.asr.vocabulary.map { $0.lowercased() })
    if let session { known.formUnion(session.dictionary.map { $0.lowercased() }) }
    // Verbose per-word trace (heard words, candidates, recovery/correction
    // decisions): live-only at `.debug`, gated by the DEBUG "Log speech
    // interventions" toggle. The net result is logged always-on below.
    let log: ((String) -> Void)? = UserDefaults.standard.bool(forKey: "logSpeechInterventions")
      ? { DiagnosticsLog.verboseTrace($0) }
      : nil
    let result = RecognitionPostProcessor(interventions: speechProfile.asr)
      .process(utterance, knownWords: known, log: log)
    DiagnosticsLog.postProcess(heard: utterance.best, result: result)
    return result
  }

  // MARK: - Internal state

  /// The config the recognizer is currently running under, so a route/input change
  /// only restarts it when the effective config actually moves. Nil when not listening.
  private var activeListeningConfig: ListeningSessionConfig?

  private var voiceAuthChecked = false
  private var hasNarratedOpening = false
  /// Guards `setListening` against re-entry while its (first-launch) auth
  /// await is in flight — without it, a mic tap during the permission prompt
  /// would race `voiceAuthChecked` and double-prompt.
  private var listeningTransitionInFlight = false

  /// The entries spoken by the most recent narration pass — game response
  /// or opening. Used by the "reread" coordinator command.
  private var lastNarratedEntries: [StyledText] = []

  /// Bumped on every `present(_:)`; lets a presentation know whether a newer
  /// readout (or a clear) has superseded it before it auto-dismisses.
  private var readoutToken = 0

  /// How long the readout overlay lingers when narration can't time the dismissal
  /// — the Simulator, where TTS is unavailable, so `speak` returns immediately.
  private static let readoutFallbackLinger: Duration = .seconds(6)

  // MARK: - Voice lifecycle (two axes)

  /// Called once when the game view appears. Narration (the accessibility voice)
  /// is free and on by default, so the opening is read regardless of the mic.
  /// Listening auto-starts only when the game's gate allows voice commands and
  /// "Play using my voice" is on; `setListening` won't fire its own `onChange`
  /// on open, so this is the initial sync.
  func startOnAppear() async {
    // Warm the neural model early so the opening narration doesn't pay the
    // ~2-3s cold start. Self-gates on `usesNeuralVoice`, so it's a no-op when
    // neural is locked or off.
    synthesizer.warmUpKokoro()
    narrateOpeningIfNeeded()
    if voiceCommandsAllowed() && UserDefaults.standard.bool(forKey: "voiceInput") {
      await setListening(true)
    }
  }

  /// Turn the recognizer on or off. Turning it on is refused while the game's
  /// gate says voice commands aren't allowed — the one choke point, so the
  /// Settings toggle (live for every user) is safe to flip inside a locked game.
  func setListening(_ enabled: Bool) async {
    guard !listeningTransitionInFlight else { return }
    listeningTransitionInFlight = true
    defer { listeningTransitionInFlight = false }
    if enabled {
      guard voiceCommandsAllowed() else { return }
      if !voiceAuthChecked {
        let granted = await recognizer.requestAuthorization()
        voiceAuthChecked = true
        if !granted { isListening = false; return }
      }
      isListening = true
      recognizer.onUtterance = { [weak self] utterance in
        guard let self else { return }
        let trimmed = postProcess(utterance).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await self.dispatch(text: trimmed, fromVoice: true) }
      }
      startRecognizer()
      narrateOpeningIfNeeded()
    } else {
      isListening = false
      recognizer.stopContinuous()
      activeListeningConfig = nil
    }
  }

  /// (Re)start continuous recognition with the current routing config. Factored so
  /// both the initial mic-on and a mid-session route/input change run the same path.
  private func startRecognizer() {
    let config = audioRoute.currentConfig()
    activeListeningConfig = config
    recognizer.startContinuous(config: config) { [weak self] in
      self?.composedContextualStrings() ?? []
    }
  }

  /// Restart the recognizer when a route or input change actually moves the session
  /// config — the user picking a different mic, or AirPods (dis)connecting mid-game.
  /// Compares against the live config so redundant route-change notifications don't
  /// churn the engine. No-op when not listening.
  private func reconfigureListeningIfNeeded() {
    guard isListening else {
      DiagnosticsLog.recognizerReconfigure(listening: false, changed: false, action: "skip")
      return
    }
    let fresh = audioRoute.currentConfig()
    let changed = fresh != activeListeningConfig
    DiagnosticsLog.recognizerReconfigure(
      listening: true, changed: changed, action: changed ? "restart" : "skip")
    guard changed else { return }
    recognizer.stopContinuous()
    startRecognizer()
  }

  func setSpeaking(_ enabled: Bool) {
    guard synthesizer.isAvailable else { return }   // TTS off in the Simulator
    isSpeaking = enabled
    if enabled {
      narrateOpeningIfNeeded()
    } else {
      synthesizer.stop()
    }
  }

  /// Releases voice resources when the game view goes away (e.g. navigating
  /// back to the library). Without this the recognizer's audio engine and
  /// voice-processing unit keep running after the game closes, so opening the
  /// next game starts a second engine on top of the first.
  func tearDown() {
    recognizer.stopContinuous()
    synthesizer.stop()
    isListening = false
    activeListeningConfig = nil
  }

  // MARK: - Dispatch

  /// Top-level entry point for every input — voice or typed. Routes to
  /// either a coordinator command (when the utterance begins with the
  /// wake word) or to the game's parser.
  func dispatch(text: String, fromVoice: Bool) async {
    // Any fresh input dismisses a showing readout — a new command supersedes it,
    // and a game command shouldn't leave a stale overlay floating over the reply.
    activeReadout = nil
    let decision = Self.decide(text: text, wakeWord: wakeWord, isNarrating: synthesizer.isSpeaking)
    // Always-on breadcrumb: why an input was routed to the game, a coordinator
    // command, or ignored — the trail that explains a command that never executed.
    DiagnosticsLog.dispatchDecision(text: text, decision: Self.describe(decision), fromVoice: fromVoice)
    switch decision {
    case .coordinator(let command): await handleCoordinator(command)
    case .ignore: return
    case .game: await sendToGame(text: text, fromVoice: fromVoice)
    }
  }

  /// A short, log-safe description of a routing decision.
  private static func describe(_ decision: DispatchDecision) -> String {
    switch decision {
    case .game: return "game"
    case .ignore: return "ignore"
    case .coordinator(let command): return "coordinator(\(command))"
    }
  }

  // MARK: - Wake-word classification

  enum CoordinatorCommand: Equatable {
    case reread
    case stop
    case faster
    case slower
    case help
    case windows
    case window(Int)
    case history
    case input(Int)
    case keywords
  }

  enum DispatchDecision: Equatable {
    case coordinator(CoordinatorCommand)
    case game
    case ignore
  }

  /// Pure routing decision. `.game` means "forward the original text to the
  /// parser"; `.ignore` covers addressed-but-unparsed and bare-while-narrating.
  static func decide(text: String, wakeWord: String, isNarrating: Bool) -> DispatchDecision {
    let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let wake = normalizedWakeWord(wakeWord)
    if isAddressed(lower, wakeWord: wake) {
      if let command = VoiceCommandCatalog.parse(stripWakeWord(from: lower, wakeWord: wake)) {
        return .coordinator(command)
      }
      return .ignore
    }
    // The recognizer often runs the wake word and a short command together into
    // a single token ("game stop" → "GameStop"), leaving no separator for
    // `isAddressed`. Accept that ONLY when the remainder after the wake-word
    // prefix is itself a known command — otherwise a real game word that merely
    // starts with the wake word (e.g. "gamekeeper") must still reach the parser.
    if lower.hasPrefix(wake),
       let command = VoiceCommandCatalog.parse(String(lower.dropFirst(wake.count))) {
      return .coordinator(command)
    }
    // A bare utterance while narrating is dropped — whether the game wants a
    // line or a single key, only "<wake> …" commands interrupt narration. The
    // recognizer would otherwise mistake the narration audio for input.
    return isNarrating ? .ignore : .game
  }

  static func normalizedWakeWord(_ raw: String?) -> String {
    let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.isEmpty ? "game" : trimmed
  }

  /// Characters allowed between the wake word and the command that follows it
  /// ("game, stop" / "game stop" / "game: stop"). Single source of truth for
  /// both addressing and stripping so the two can't drift apart.
  private static let wakeWordSeparators: Set<Character> = [" ", ",", ".", "?", "!", ":"]

  private static func isAddressed(_ lower: String, wakeWord: String) -> Bool {
    if lower == wakeWord { return true }
    guard lower.hasPrefix(wakeWord) else { return false }
    let nextIndex = lower.index(lower.startIndex, offsetBy: wakeWord.count)
    guard nextIndex < lower.endIndex else { return true }
    return wakeWordSeparators.contains(lower[nextIndex])
  }

  private static func stripWakeWord(from lower: String, wakeWord: String) -> String {
    let after = lower.dropFirst(wakeWord.count)
    let trimmed = after.drop(while: { wakeWordSeparators.contains($0) })
    return String(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Coordinator command handlers

  private func handleCoordinator(_ command: CoordinatorCommand) async {
    switch command {
    case .reread:
      await rereadLast()
    case .stop:
      synthesizer.stop()
    case .faster:
      adjustSpeechRate(by: 0.05)
    case .slower:
      adjustSpeechRate(by: -0.05)
    case .help:
      await present(VoiceCommandCatalog.helpReadout())
    case .windows:
      await handleWindows()
    case .window(let number):
      await handleWindow(number)
    case .history:
      await handleHistory()
    case .input(let number):
      await handleInput(number)
    case .keywords:
      await handleKeywords()
    }
  }

  // MARK: - Keywords

  private func handleKeywords() async {
    guard let session else { return }
    let words = KeywordScanner.keywords(in: session.lastResponse)
    guard !words.isEmpty else {
      await speakNotice("No highlighted words in the last passage.")
      return
    }
    await present(KeywordScanner.readout(words))
  }

  // MARK: - History

  private func handleHistory() async {
    guard let session else { return }
    guard !session.inputHistory.isEmpty else {
      await speakNotice("No commands yet.")
      return
    }
    await present(InputHistory.readout(session.inputHistory))
  }

  /// Re-issue a past line command (1 = most recent) as if typed now, so the
  /// game's response narrates under the usual rules. No overlay.
  private func handleInput(_ number: Int) async {
    guard let session else { return }
    let recents = InputHistory.recent(session.inputHistory)
    guard number >= 1, number <= recents.count else {
      await speakNotice("There's no input \(number). Say history for the list.")
      return
    }
    await sendToGame(text: recents[number - 1], fromVoice: false)
  }

  // MARK: - Windows

  private func handleWindows() async {
    guard let session else { return }
    await present(WindowInventory.listReadout(slots: windowSlots(session)))
  }

  private func handleWindow(_ number: Int) async {
    guard let session else { return }
    guard let slot = windowSlots(session).first(where: { $0.number == number }) else {
      await speakNotice("There's no window \(number). Say windows for the list.")
      return
    }
    await present(WindowInventory.contentReadout(for: slot))
  }

  private func windowSlots(_ session: InterpreterSession) -> [WindowInventory.Slot] {
    WindowInventory.slots(
      storyTop: session.primaryBufferTop,
      lastResponse: session.lastResponse,
      statusWindows: session.statusWindows,
      secondaryBuffers: session.secondaryBufferWindows)
  }

  /// Narrate a brief coordinator notice with no overlay — e.g. an out-of-range
  /// `window N` / `input N`. Speaks unconditionally, like the readback commands.
  private func speakNotice(_ text: String) async {
    await synthesizer.speak(StyledText.narration(text))
  }

  /// Show a readout in the overlay and narrate it, then auto-dismiss. Narrates
  /// unconditionally (independent of the `isSpeaking` axis, like `reread`) — the
  /// user asked for this by voice. The dismissal is timed by narration on device;
  /// where TTS is unavailable (Simulator) it lingers briefly instead. A newer
  /// `present` (or a `dispatch` clear) bumps `readoutToken`, so a stale
  /// presentation won't wipe the overlay out from under its successor.
  private func present(_ readout: VoiceReadout) async {
    readoutToken += 1
    let token = readoutToken
    activeReadout = readout
    if synthesizer.isAvailable {
      await synthesizer.speak(StyledText.narration(readout.spokenText))
    } else {
      try? await Task.sleep(for: Self.readoutFallbackLinger)
    }
    if readoutToken == token { activeReadout = nil }
  }

  private func rereadLast() async {
    let entries = lastNarratedEntries
    guard !entries.isEmpty else { return }
    await synthesizer.speak(entries)
  }

  private func adjustSpeechRate(by delta: Float) {
    let stored = UserDefaults.standard.float(forKey: "speechRate")
    let current = stored > 0 ? stored : AVSpeechUtteranceDefaultSpeechRate
    let next = max(
      AVSpeechUtteranceMinimumSpeechRate,
      min(AVSpeechUtteranceMaximumSpeechRate, current + delta)
    )
    UserDefaults.standard.set(Double(next), forKey: "speechRate")
  }

  // MARK: - Game send (line + char, with TTS narration)

  /// Commands that swap in a different game state. Most Infocom-era
  /// Z-machine games don't auto-clear the buffer on these, so the visible
  /// log piles up the old play history under the new state and the
  /// synthesizer would otherwise narrate the entire pre-restore log.
  private static let stateResetCommands: Set<String> = [
    "restore", "restart", "load", "load game"
  ]

  /// "Speak back my commands" (Reading Text settings, default on): gates reading the
  /// player's own command back before the game's reply. Read live so toggling it
  /// takes effect on the next command.
  private var repeatsCommands: Bool {
    UserDefaults.standard.object(forKey: "repeatCommands") as? Bool ?? true
  }

  private func sendToGame(text: String, fromVoice: Bool) async {
    guard let session, let mode = session.inputMode else { return }

    let payload = preparePayload(text: text, mode: mode, fromVoice: fromVoice)
    guard !payload.isEmpty else { return }

    let isStateReset = (mode == .line)
      && Self.stateResetCommands.contains(payload.lowercased())
    let shouldNarrate = isSpeaking

    switch mode {
    case .line: await session.send(payload)
    case .char: await session.sendCharacter(payload)
    }

    // The session computes the response window itself — it's the only layer that
    // knows whether the update redrew the screen, which invalidates any pre-send
    // transcript index (AMFV clears + redraws after its intro keypress).
    let responseEntries = session.lastResponse

    if isStateReset && !responseEntries.isEmpty {
      session.trimTranscript(keepingSuffix: session.transcript.count - session.lastResponseStart)
    }

    // Read the player's own command back before its result, so an eyes-free player
    // hears the final command that was actually sent — keyboard autocorrect or ASR
    // recovery already applied. Gated by "Speak back my commands" (default on). Line
    // input only: single keys (menus, y/n) would chatter. `speakCommandEcho` uses a
    // lower pitch (system voice) so the command is audibly distinct from the reply.
    if shouldNarrate && mode == .line && repeatsCommands {
      await synthesizer.speakCommandEcho(payload)
    }

    if shouldNarrate && !isStateReset {
      await synthesizer.speak(responseEntries)
      if !responseEntries.isEmpty {
        lastNarratedEntries = responseEntries
      }
    }
  }

  /// Named special keys glkapi maps to keycodes (`return` → keycode_Return), passed
  /// through intact so the typed char path doesn't truncate "return" to "r".
  private static let specialKeys: Set<String> = [
    "return", "escape", "tab", "delete", "up", "down", "left", "right", "pageup", "pagedown", "home", "end"
  ]

  private func preparePayload(
    text: String,
    mode: RemGlkUpdate.InputType,
    fromVoice: Bool
  ) -> String {
    switch mode {
    case .line:
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    case .char:
      if fromVoice { return Self.characterFromUtterance(text) }
      let lower = text.lowercased()
      if Self.specialKeys.contains(lower) { return lower }
      return String(text.first ?? " ")
    }
  }

  /// Spoken number words → digits, so a single-key menu like Blue Lacuna's
  /// keyword screen ("press 0–5") is answerable by voice. Bare digits ("0") fall
  /// through to the single-character path below.
  private static let digitWords: [String: String] = [
    "zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3", "four": "4",
    "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"
  ]

  /// Maps a free-form spoken utterance to a single Glk character-input
  /// value: "space" → " ", "yes" → "y", "zero" → "0", "return"/"enter" → "return".
  static func characterFromUtterance(_ utterance: String) -> String {
    let lower = utterance.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if lower.contains("space") { return " " }
    if lower.contains("return") || lower.contains("enter") { return "return" }
    if lower.contains("escape") { return "escape" }
    if lower == "yes" || lower == "y" || lower.hasPrefix("yes ") { return "y" }
    if lower == "no" || lower == "n" || lower.hasPrefix("no ") { return "n" }
    if let digit = digitWords[lower] { return digit }
    return String(lower.first(where: { !$0.isWhitespace }) ?? " ")
  }

  // MARK: - Opening narration

  /// Speaks the game's entry point aloud — once per game session, when narration
  /// is active. A fresh game reads its whole opening transcript (including the
  /// mood-setting prose before the copyright/serial line). A restored game
  /// already has prior commands in the transcript, so it reads just the latest
  /// block (where the player left off) rather than the full history or nothing.
  func narrateOpeningIfNeeded() {
    guard let session, isSpeaking else { return }
    guard !hasNarratedOpening else { return }

    let entry = session.transcript.contains(where: \.isUserInput)
      ? session.lastResponse
      : session.transcript
    guard !entry.isEmpty else { return }

    hasNarratedOpening = true
    Task {
      await synthesizer.speak(entry)
      lastNarratedEntries = entry
    }
  }

  // MARK: - Contextual strings

  /// Composes the recognizer's contextual-strings list, rebuilt every
  /// cycle so per-utterance biasing adapts to the current game state.
  /// Order: canonical IF terms → recent transcript vocabulary → full
  /// parser dictionary. Duplicates dropped case-insensitively.
  private func composedContextualStrings() -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    let wake = wakeWord
    if seen.insert(wake).inserted { ordered.append(wake) }
    // Profile vocabulary (game acronyms like PEOF) leads the canonical terms — the
    // recognizer weights earliest entries most.
    for word in speechProfile.asr.vocabulary where seen.insert(word.lowercased()).inserted {
      ordered.append(word)
    }
    for word in IFCanonicalTerms.all where seen.insert(word.lowercased()).inserted {
      ordered.append(word)
    }
    if let session {
      let transcriptWords = TranscriptVocabulary.extract(from: session.transcript)
      for word in transcriptWords where seen.insert(word.lowercased()).inserted {
        ordered.append(word)
      }
      for word in session.dictionary where seen.insert(word.lowercased()).inserted {
        ordered.append(word)
      }
    }
    return ordered
  }

  /// Test seam — exposes the composed bias list without a live session.
  func contextualStringsForTesting() -> [String] { composedContextualStrings() }
}
