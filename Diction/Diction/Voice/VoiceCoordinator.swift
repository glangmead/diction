import Foundation
import AVFoundation

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
final class VoiceCoordinator {
  // MARK: - View-observable state

  /// Input axis — is the app listening to the user.
  private(set) var isListening = true
  /// Output axis — does the app speak. Toggling off stops the current sentence.
  private(set) var isSpeaking = true

  // MARK: - Owned services

  let recognizer = SpeechRecognizer()
  let synthesizer = SpeechSynthesizer()

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
  }

  // MARK: - Internal state

  private var voiceAuthChecked = false
  private var hasNarratedOpening = false
  /// Guards `setListening` against re-entry while its (first-launch) auth
  /// await is in flight — without it, a mic tap during the permission prompt
  /// would race `voiceAuthChecked` and double-prompt.
  private var listeningTransitionInFlight = false

  /// The entries spoken by the most recent narration pass — game response
  /// or opening. Used by the "reread" coordinator command.
  private var lastNarratedEntries: [StyledText] = []

  // MARK: - Voice lifecycle (two axes)

  /// Called once when the game view appears; applies the default-on axes.
  func startOnAppear() async {
    await setListening(true)
  }

  func setListening(_ enabled: Bool) async {
    guard !listeningTransitionInFlight else { return }
    listeningTransitionInFlight = true
    defer { listeningTransitionInFlight = false }
    if enabled {
      if !voiceAuthChecked {
        let granted = await recognizer.requestAuthorization()
        voiceAuthChecked = true
        if !granted { isListening = false; return }
      }
      isListening = true
      recognizer.onUtterance = { [weak self] utterance in
        guard let self else { return }
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await self.dispatch(text: trimmed, fromVoice: true) }
      }
      recognizer.startContinuous { [weak self] in
        self?.composedContextualStrings() ?? []
      }
      narrateOpeningIfNeeded()
    } else {
      isListening = false
      recognizer.stopContinuous()
    }
  }

  func setSpeaking(_ enabled: Bool) {
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
  }

  // MARK: - Dispatch

  /// Top-level entry point for every input — voice or typed. Routes to
  /// either a coordinator command (when the utterance begins with the
  /// wake word) or to the game's parser.
  func dispatch(text: String, fromVoice: Bool) async {
    switch Self.decide(text: text, wakeWord: wakeWord, isNarrating: synthesizer.isSpeaking) {
    case .coordinator(let command): await handleCoordinator(command)
    case .ignore: return
    case .game: await sendToGame(text: text, fromVoice: fromVoice)
    }
  }

  // MARK: - Wake-word classification

  enum CoordinatorCommand: Equatable {
    case reread
    case stop
    case faster
    case slower
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
      if let command = parseCoordinatorCommand(stripWakeWord(from: lower, wakeWord: wake)) {
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
       let command = parseCoordinatorCommand(String(lower.dropFirst(wake.count))) {
      return .coordinator(command)
    }
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

  private static func parseCoordinatorCommand(_ text: String) -> CoordinatorCommand? {
    switch text {
    case "reread", "repeat", "again", "say that again", "say again":
      return .reread
    case "stop", "pause", "quiet", "shut up", "be quiet":
      return .stop
    case "faster", "speed up", "speak faster", "talk faster":
      return .faster
    case "slower", "slow down", "speak slower", "talk slower":
      return .slower
    default:
      return nil
    }
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
    }
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

  private func sendToGame(text: String, fromVoice: Bool) async {
    guard let session, let mode = session.inputMode else { return }

    let payload = preparePayload(text: text, mode: mode, fromVoice: fromVoice)
    guard !payload.isEmpty else { return }

    let isStateReset = (mode == .line)
      && Self.stateResetCommands.contains(payload.lowercased())
    let shouldNarrate = isSpeaking

    let indexBefore = session.transcript.count
    switch mode {
    case .line: await session.send(payload)
    case .char: await session.sendCharacter(payload)
    }

    let grew = session.transcript.count >= indexBefore
    let responseEntries = grew
      ? Array(session.transcript[indexBefore...].filter { !$0.isUserInput })
      : []

    if isStateReset && grew {
      session.trimTranscript(keepingSuffix: session.transcript.count - indexBefore)
    }

    if shouldNarrate && !isStateReset {
      await synthesizer.speak(responseEntries)
      if !responseEntries.isEmpty {
        lastNarratedEntries = responseEntries
      }
    }
  }

  private func preparePayload(
    text: String,
    mode: RemGlkUpdate.InputType,
    fromVoice: Bool
  ) -> String {
    switch mode {
    case .line:
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    case .char:
      return fromVoice
        ? Self.characterFromUtterance(text)
        : String(text.first ?? " ")
    }
  }

  /// Maps a free-form spoken utterance to a single Glk character-input
  /// value: "space" → " ", "yes" → "y", "return"/"enter" → "return", etc.
  private static func characterFromUtterance(_ utterance: String) -> String {
    let lower = utterance.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if lower.contains("space") { return " " }
    if lower.contains("return") || lower.contains("enter") { return "return" }
    if lower.contains("escape") { return "escape" }
    if lower == "yes" || lower == "y" || lower.hasPrefix("yes ") { return "y" }
    if lower == "no" || lower == "n" || lower.hasPrefix("no ") { return "n" }
    return String(lower.first(where: { !$0.isWhitespace }) ?? " ")
  }

  // MARK: - Opening narration

  /// Speaks the game's opening room state aloud — once per game session,
  /// only when narration is active and the player hasn't sent any
  /// commands yet. Title / copyright / serial-number boilerplate is
  /// filtered out by `InitialNarration`.
  func narrateOpeningIfNeeded() {
    guard let session, isSpeaking else { return }
    guard !hasNarratedOpening else { return }
    guard !session.transcript.contains(where: \.isUserInput) else { return }

    let opening = InitialNarration.entries(from: session.transcript)
    guard !opening.isEmpty else { return }

    hasNarratedOpening = true
    Task {
      await synthesizer.speak(opening)
      lastNarratedEntries = opening
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
