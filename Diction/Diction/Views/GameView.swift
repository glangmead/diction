import SwiftUI

struct GameView: View {
  let storyFile: StoryFile

  @Environment(VoiceWarmer.self) private var voiceWarmer
  @Environment(StoreManager.self) private var store
  @State private var session = InterpreterSession()
  @State private var coordinator = VoiceCoordinator()
  @State private var commandText = ""
  /// Separate from `commandText` because the char-input field auto-submits
  /// on every character and we don't want that behavior leaking into the
  /// line-input field when the mode flips back.
  @State private var charInputText = ""
  @State private var isLoading = true
  @State private var loadError: String?
  @State private var showingSettings = false
  @State private var showingResetConfirm = false
  /// Bumped to restart the game from scratch: the load `.task` is keyed on it,
  /// so changing it re-runs the load against a freshly created session.
  @State private var reloadToken = 0
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
    .background(.gameBackground)
    .navigationTitle(storyFile.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarBackground(Color(.gameSurface), for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) { settingsButton }
      ToolbarItem(placement: .topBarTrailing) { voiceLoadingIndicator }
      ToolbarItem(placement: .topBarTrailing) { micToggle }
      ToolbarItem(placement: .topBarTrailing) { speakerToggle }
      ToolbarItem(placement: .topBarTrailing) { resetButton }
    }
    .sheet(isPresented: $showingSettings) {
      SettingsView()
    }
    .confirmationDialog(
      "Start over?", isPresented: $showingResetConfirm, titleVisibility: .visible
    ) {
      Button("Start Over", role: .destructive) { resetGame() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This erases your saved progress in \(storyFile.title) and restarts from the beginning.")
    }
    .task(id: reloadToken) {
      coordinator.attach(session: session)
      coordinator.useSharedVoice(voiceWarmer)
      coordinator.useEntitlement(store)
      session.snapshotStore = .default   // per-turn autosave + resume-on-open
      do {
        try await session.load(storyFile.url)
        isLoading = false
        await coordinator.startOnAppear()
      } catch {
        // Surface the interpreter's own failure detail (the bridge/VM error
        // captured in `lastError`) rather than the generic wrapper, so load
        // failures are diagnosable instead of an opaque "Failed to load story".
        loadError = session.lastError ?? "Failed to load story: \(error)"
        isLoading = false
      }
    }
    .onChange(of: coordinator.recognizer.transcription) { _, new in
      // The field mirrors whatever the recognizer currently hears, so the user
      // sees the live transcription. Crucially this mirrors the empty value too:
      // continuous mode resets `transcription` to "" at the start of each cycle —
      // i.e. right after an utterance finalizes and is dispatched — so the
      // executed command clears instead of lingering in the field. (Guarding on
      // `!new.isEmpty` was the bug: it skipped that reset and stuck the last
      // utterance there forever, since `isListening` never drops between cycles.)
      if coordinator.recognizer.isListening {
        commandText = new
      }
    }
    .onChange(of: coordinator.recognizer.isListening) { _, listening in
      // Turning the mic off clears any lingering partial transcription. (In
      // continuous mode `isListening` stays true between utterances, so this
      // fires only on a real mic-off — the per-utterance clear is handled above.)
      if !listening { commandText = "" }
    }
    .onDisappear {
      // Navigating back to the library tears down this view. Release the audio
      // engine and cleanly stop the interpreter before the session is gone, so
      // re-opening a game doesn't race a still-running first one.
      coordinator.tearDown()
      let session = session
      Task { await session.shutdown() }
    }
  }

  // MARK: - Toolbar

  private var settingsButton: some View {
    Button {
      showingSettings = true
    } label: {
      Image(systemName: "gearshape")
    }
    .accessibilityLabel("Settings")
  }

  private var micToggle: some View {
    Button {
      Task { await coordinator.setListening(!coordinator.isListening) }
    } label: {
      Image(systemName: coordinator.isListening ? "mic.fill" : "mic.slash")
        .foregroundStyle(coordinator.isListening ? .blue : .gray)
    }
    .accessibilityLabel(coordinator.isListening ? "Stop listening" : "Start listening")
    .accessibilityHint("Whether the app listens to your voice for commands.")
  }

  private var speakerToggle: some View {
    Button {
      coordinator.setSpeaking(!coordinator.isSpeaking)
    } label: {
      Image(systemName: coordinator.isSpeaking ? "speaker.wave.2.fill" : "speaker.slash")
        .foregroundStyle(coordinator.isSpeaking ? .blue : .gray)
    }
    .accessibilityLabel(coordinator.isSpeaking ? "Mute narration" : "Unmute narration")
    .accessibilityHint("Whether the app reads game responses aloud. Muting stops the current sentence.")
  }

  /// Shown while the neural narration voice loads (the model cold-start can take
  /// ~15 s). Collapses to nothing once the voice is ready, fails to load, or
  /// when the neural path is off.
  @ViewBuilder
  private var voiceLoadingIndicator: some View {
    if coordinator.synthesizer.isPreparingVoice {
      HStack(spacing: 5) {
        ProgressView()
          .controlSize(.small)
        Text("Loading voice")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Loading narration voice")
    }
  }

  // MARK: - Transcript rendering

  private var transcriptView: some View {
    ZStack {
      InterpreterWebView(webView: session.interpreterWebView)
      if isLoading {
        ProgressView()
      }
    }
    // The WebView is the reading surface and must fill the space the old
    // greedy ScrollView did — without this the representable collapses toward
    // its (zero) intrinsic height and only a sliver shows.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Input bar

  @ViewBuilder
  private var inputBar: some View {
    if session.inputMode == .char {
      charInputBar
    } else {
      lineInputBar
    }
  }

  /// Visual + VoiceOver hint for the single-keypress field.
  private static let charInputHint = "y / n / 1 / …"

  /// The "listening paused" placeholder text, or `nil` when it shouldn't show.
  /// Non-nil only while narration is playing and the user hasn't tapped into
  /// the field (typing shouldn't be nagged). Read inside `body` via the input
  /// bars' `prompt:` / `accessibilityValue`, so Observation tracks the reads of
  /// `synthesizer.isSpeaking` and `inputFocused` and re-renders the bar.
  private var narrationPausedText: String? {
    guard NarrationInputPrompt.isVisible(
      isNarrating: coordinator.synthesizer.isSpeaking,
      isFieldFocused: inputFocused
    ) else { return nil }
    return NarrationInputPrompt.message(wakeWord: coordinator.wakeWord)
  }

  private var narrationPausedPrompt: Text? {
    narrationPausedText.map { Text($0) }
  }

  private var lineInputBar: some View {
    HStack(spacing: 8) {
      Text(">")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gray)
      TextField("", text: $commandText, prompt: narrationPausedPrompt)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gameText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($inputFocused)
        .onSubmit { dispatchTyped(commandText) }
        .submitLabel(.send)
        .accessibilityLabel("Enter command")
        .accessibilityValue(narrationPausedText ?? commandText)
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.gameSurface)
  }

  /// Shown when the interpreter is blocked on a single-keypress input
  /// (`glk_request_char_event`). The text field auto-submits on every
  /// keystroke so the user doesn't have to hit return; the "Continue"
  /// button covers the common "press SPACE to begin" case.
  private var charInputBar: some View {
    HStack(spacing: 8) {
      Text("Key:")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gray)
      TextField("", text: $charInputText, prompt: narrationPausedPrompt ?? Text(Self.charInputHint))
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gameText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($inputFocused)
        .accessibilityLabel("Press a single key")
        .accessibilityValue(narrationPausedText ?? (charInputText.isEmpty ? Self.charInputHint : charInputText))
        .onChange(of: charInputText) { _, new in
          guard let first = new.first else { return }
          let key = String(first)
          charInputText = ""
          dispatchTyped(key)
        }
      Button("Continue") {
        dispatchTyped(" ")
      }
      .buttonStyle(.borderedProminent)
      .accessibilityHint("Sends space; the most common 'press any key' answer.")
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.gameSurface)
  }

  // MARK: - Typed dispatch

  /// Hands a typed input string (from line field, char field, or
  /// Continue button) off to the coordinator. Coordinator decides
  /// whether it's a wake-word command or a game command.
  private func dispatchTyped(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { commandText = "" }
    Task { await coordinator.dispatch(text: text, fromVoice: false) }
  }
}

// MARK: - Reset / start-over

extension GameView {
  var resetButton: some View {
    Button {
      showingResetConfirm = true
    } label: {
      Image(systemName: "arrow.clockwise")
    }
    .accessibilityLabel("Start over")
    .accessibilityHint("Erases saved progress and restarts this game from the beginning.")
  }

  /// Delete the resume snapshot and reload from scratch on a fresh session.
  func resetGame() {
    let previous = session
    Task { await previous.shutdown() }
    coordinator.tearDown()
    GameSnapshotStore.default.delete(gameID: SaveStorage.gameID(for: storyFile.url))
    session = InterpreterSession()
    loadError = nil
    isLoading = true
    reloadToken += 1
  }
}
