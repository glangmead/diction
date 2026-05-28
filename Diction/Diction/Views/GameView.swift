import SwiftUI

// Coordinates transcript rendering, two input-bar variants, voice-mode
// lifecycle, opening narration, contextual-strings composition, and the
// unified input dispatch. Splitting these would either need a separate
// `@Observable` controller (worth doing once voice features stabilize) or
// scattered helper structs the View has to plumb data into.
// swiftlint:disable:next type_body_length
struct GameView: View {
  let storyFile: StoryFile

  @State private var session = InterpreterSession()
  @State private var commandText = ""
  /// Separate from `commandText` because the char-input field auto-submits
  /// on every character and we don't want that behavior leaking into the
  /// line-input field when the mode flips back.
  @State private var charInputText = ""
  @State private var isVoiceMode = false
  @State private var isLoading = true
  @State private var loadError: String?

  /// True once we've asked the user for Speech + microphone permissions.
  /// Avoids re-prompting every time voice mode is toggled.
  @State private var voiceAuthChecked = false

  /// Whether we've narrated the game's initial room state. Set to true the
  /// first time voice mode goes active on a fresh game — prevents replaying
  /// the opening every time the user toggles voice mode or unmutes.
  @State private var hasNarratedOpening = false

  @State private var recognizer = SpeechRecognizer()
  @State private var synthesizer = SpeechSynthesizer()
  @FocusState private var inputFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      transcriptView

      if let error = loadError {
        Text(error)
          .font(.callout)
          .foregroundStyle(.red)
          .padding()
      }

      if session.isAwaitingInput && loadError == nil {
        inputBar
      }
    }
    .background(Color(white: 0.08))
    .navigationTitle(storyFile.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarColorScheme(.dark, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await toggleVoiceMode() }
        } label: {
          Image(systemName: isVoiceMode ? "mic.fill" : "mic.slash")
            .foregroundStyle(isVoiceMode ? .blue : .gray)
        }
        .accessibilityLabel(isVoiceMode ? "Disable voice mode" : "Enable voice mode")
        .accessibilityHint("Voice mode: speak commands and hear responses.")
      }
    }
    .task {
      do {
        try await session.load(storyFile.url)
        isLoading = false
        inputFocused = true
      } catch {
        loadError = "Failed to load story: \(error)"
        isLoading = false
      }
    }
    .onChange(of: recognizer.transcription) { _, new in
      // Live-update the input field with partial transcription while
      // listening, so the user sees what's being heard.
      if recognizer.isListening && !new.isEmpty {
        commandText = new
      }
    }
  }

  // MARK: - Transcript rendering

  private var transcriptView: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          if isLoading {
            ProgressView()
              .padding()
          }
          ForEach(session.transcript) { entry in
            StyledTextLineView(entry: entry)
              .id(entry.id)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          // Zero-height anchor at the true end of the LazyVStack. Scrolling
          // to this stable id always lands at the bottom, even when the
          // last entry's height is still being computed.
          Color.clear
            .frame(height: 1)
            .id(Self.bottomAnchorID)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
      }
      .onChange(of: session.transcriptRevision) {
        // Defer one runloop tick so LazyVStack has a chance to lay out
        // any newly-appended (or in-place-merged) content before we
        // measure where the bottom actually is.
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(16))
          withAnimation {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
          }
        }
      }
    }
  }

  private static let bottomAnchorID = "diction-transcript-bottom"

  // MARK: - Input bar

  @ViewBuilder
  private var inputBar: some View {
    if session.inputMode == .char {
      charInputBar
    } else {
      lineInputBar
    }
  }

  private var lineInputBar: some View {
    HStack(spacing: 8) {
      Text(">")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gray)
      TextField("", text: $commandText)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(Color(white: 0.9))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($inputFocused)
        .onSubmit { sendInput(commandText) }
        .submitLabel(.send)
        .accessibilityLabel("Enter command")
      if isVoiceMode {
        listenButton
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(Color(white: 0.12))
  }

  /// Shown when the interpreter is blocked on a single-keypress input
  /// (`glk_request_char_event`). The text field auto-submits on every
  /// keystroke so the user doesn't have to hit return; the "Continue"
  /// button covers the common "press SPACE to begin" case without
  /// requiring the keyboard at all.
  private var charInputBar: some View {
    HStack(spacing: 8) {
      Text("Key:")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gray)
      TextField("y / n / 1 / …", text: $charInputText)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(Color(white: 0.9))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($inputFocused)
        .accessibilityLabel("Press a single key")
        .onChange(of: charInputText) { _, new in
          guard let first = new.first else { return }
          let key = String(first)
          charInputText = ""
          sendInput(key)
        }
      Button("Continue") {
        sendInput(" ")
      }
      .buttonStyle(.borderedProminent)
      .accessibilityHint("Sends space; the most common 'press any key' answer.")
      if isVoiceMode {
        listenButton
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(Color(white: 0.12))
  }

  private var listenButton: some View {
    Button {
      let willUnmute = recognizer.isUserMuted
      recognizer.setUserMuted(!recognizer.isUserMuted)
      if willUnmute {
        narrateOpeningIfNeeded()
      }
    } label: {
      Image(systemName: recognizer.isUserMuted ? "mic.slash.fill" : "mic.fill")
        .font(.title3)
        .foregroundStyle(.white)
        .frame(width: 36, height: 36)
        .background(Circle().fill(recognizer.isUserMuted ? .gray : .red))
    }
    .accessibilityLabel(recognizer.isUserMuted ? "Unmute microphone" : "Mute microphone")
    .accessibilityHint("Voice mode keeps listening; tap to mute or unmute.")
  }

  // MARK: - Actions

  /// Commands that swap in a different game state. Most Infocom-era
  /// Z-machine games don't auto-clear the buffer on these, so the visible
  /// log piles up the old play history under the new state and the
  /// synthesizer would otherwise narrate the entire pre-restore log.
  private static let stateResetCommands: Set<String> = [
    "restore", "restart", "load", "load game"
  ]

  /// Single entry point for getting any input — text or voice, line or
  /// char — to the interpreter. Handles the choice of `session.send` vs
  /// `session.sendCharacter`, voice-mode mic suspension, state-reset
  /// trimming, and response narration.
  private func sendInput(_ rawInput: String, fromVoice: Bool = false) {
    guard let mode = session.inputMode else { return }
    let payload = preparePayload(rawInput, mode: mode, fromVoice: fromVoice)
    guard !payload.isEmpty else { return }

    let isStateReset = (mode == .line)
      && Self.stateResetCommands.contains(payload.lowercased())

    // Capture voice-mode state synchronously so toggling voice mode mid-
    // response doesn't leave the recognizer suspended.
    let voiceCoordinated = isVoiceMode
    if voiceCoordinated {
      recognizer.setExternallySuspended(true)
    }

    Task {
      await dispatchAndNarrate(
        payload: payload,
        mode: mode,
        isStateReset: isStateReset,
        voiceCoordinated: voiceCoordinated
      )
    }
  }

  private func preparePayload(
    _ rawInput: String,
    mode: RemGlkUpdate.InputType,
    fromVoice: Bool
  ) -> String {
    switch mode {
    case .line:
      let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { commandText = "" }
      return trimmed
    case .char:
      charInputText = ""
      return fromVoice
        ? Self.characterFromUtterance(rawInput)
        : String(rawInput.first ?? " ")
    }
  }

  private func dispatchAndNarrate(
    payload: String,
    mode: RemGlkUpdate.InputType,
    isStateReset: Bool,
    voiceCoordinated: Bool
  ) async {
    let indexBefore = session.transcript.count
    switch mode {
    case .line: await session.send(payload)
    case .char: await session.sendCharacter(payload)
    }

    // Capture the response slice BEFORE we trim, so we know what was
    // freshly added (even if we then collapse the visible log).
    let grew = session.transcript.count >= indexBefore
    let responseEntries = grew
      ? Array(session.transcript[indexBefore...].filter { !$0.isUserInput })
      : []

    // Visually collapse the log on state reset so the user only sees the
    // post-restore room state, not the pre-save play history.
    if isStateReset && grew {
      session.trimTranscript(keepingSuffix: session.transcript.count - indexBefore)
    }

    if voiceCoordinated {
      if !isStateReset {
        for entry in responseEntries {
          await synthesizer.speak(entry)
        }
      }
      recognizer.setExternallySuspended(false)
    }
  }

  /// Maps a free-form spoken utterance to a single Glk character-input
  /// value. Heuristic but covers the cases that actually occur: "press
  /// SPACE", y/n prompts, "press return / enter", and single-letter
  /// menu picks.
  private static func characterFromUtterance(_ utterance: String) -> String {
    let lower = utterance.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if lower.contains("space") { return " " }
    if lower.contains("return") || lower.contains("enter") { return "return" }
    if lower.contains("escape") { return "escape" }
    if lower == "yes" || lower == "y" || lower.hasPrefix("yes ") { return "y" }
    if lower == "no" || lower == "n" || lower.hasPrefix("no ") { return "n" }
    // Single-character utterance (recognizer occasionally returns this for
    // letters/digits) or fall back to the first non-space character.
    return String(lower.first(where: { !$0.isWhitespace }) ?? " ")
  }

  private func toggleVoiceMode() async {
    if isVoiceMode {
      recognizer.stopContinuous()
      synthesizer.stop()
      isVoiceMode = false
      return
    }

    if !voiceAuthChecked {
      let granted = await recognizer.requestAuthorization()
      voiceAuthChecked = true
      if !granted { return }
    }

    isVoiceMode = true
    recognizer.onUtterance = { @MainActor utterance in
      let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      sendInput(trimmed, fromVoice: true)
    }
    recognizer.startContinuous { @MainActor in
      contextualStringsForRecognition()
    }
    narrateOpeningIfNeeded()
  }

  /// Speak the game's opening room state aloud — once per game session,
  /// only when voice mode is active and the player hasn't sent any
  /// commands yet. The title / copyright / serial-number boilerplate is
  /// filtered out by `InitialNarration`.
  private func narrateOpeningIfNeeded() {
    guard isVoiceMode, !recognizer.isUserMuted else { return }
    guard !hasNarratedOpening else { return }
    guard !session.transcript.contains(where: \.isUserInput) else { return }

    let opening = InitialNarration.entries(from: session.transcript)
    guard !opening.isEmpty else { return }

    hasNarratedOpening = true
    recognizer.setExternallySuspended(true)
    Task {
      for entry in opening {
        await synthesizer.speak(entry)
      }
      recognizer.setExternallySuspended(false)
    }
  }

  /// Composes the recognizer's contextual-strings list, rebuilt every
  /// cycle so per-utterance biasing adapts to the current game state.
  /// Priority order (earliest = strongest weight): canonical IF terms,
  /// then transcript vocabulary, then full parser dictionary. Duplicates
  /// dropped case-insensitively.
  private func contextualStringsForRecognition() -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    for word in IFCanonicalTerms.all where seen.insert(word.lowercased()).inserted {
      ordered.append(word)
    }
    let transcriptWords = TranscriptVocabulary.extract(from: session.transcript)
    for word in transcriptWords where seen.insert(word.lowercased()).inserted {
      ordered.append(word)
    }
    for word in session.dictionary where seen.insert(word.lowercased()).inserted {
      ordered.append(word)
    }
    return ordered
  }
}
