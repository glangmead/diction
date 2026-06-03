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
  /// Drives the transcript scroll. Initialised to the bottom edge so play
  /// starts pinned, and re-pinned explicitly when content or the input bar
  /// changes — `.defaultScrollAnchor(.bottom)` alone stops following once the
  /// content outgrows the viewport (see `transcriptView`).
  @State private var scrollPosition = ScrollPosition(edge: .bottom)
  /// True while the transcript is parked at (or within a hair of) its bottom.
  /// Gates auto-follow so a reader who scrolls up to review history isn't
  /// yanked back down by new game output.
  @State private var isPinnedToBottom = true
  @FocusState private var inputFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      statusBar
      transcriptView

      if let error = loadError {
        Text(error)
          .font(.callout)
          .foregroundStyle(.red)
          .padding()
      }

      bottomBufferPanels

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
    }
    .sheet(isPresented: $showingSettings) {
      SettingsView()
    }
    .task {
      coordinator.attach(session: session)
      coordinator.useSharedVoice(voiceWarmer)
      coordinator.useEntitlement(store)
      do {
        try await session.load(storyFile.url)
        isLoading = false
        await coordinator.startOnAppear()
      } catch {
        loadError = "Failed to load story: \(error)"
        isLoading = false
      }
    }
    .onChange(of: coordinator.recognizer.transcription) { _, new in
      // Live-update the input field with partial transcription while
      // listening, so the user sees what's being heard.
      if coordinator.recognizer.isListening && !new.isEmpty {
        commandText = new
      }
    }
    .onChange(of: coordinator.recognizer.isListening) { _, listening in
      // After a recognition cycle finalizes, clear the input field so
      // the residual transcription doesn't linger across utterances.
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

  // MARK: - Status bar (grid windows)

  /// Grid (status) windows as a fixed-column monospaced block pinned under the
  /// toolbar — AMFV's mode / location / time / date bar, etc. Hidden while a
  /// grid is entirely blank (many games leave theirs empty). Per-run styling
  /// (reverse video, bold) is resolved on the runs but not applied here yet.
  @ViewBuilder
  private var statusBar: some View {
    ForEach(session.statusWindows.filter(Self.hasContent)) { window in
      StatusWindowView(window: window)
    }
  }

  /// True if any row carries non-whitespace content, so we don't show an
  /// empty bar.
  nonisolated private static func hasContent(_ window: GridWindowSnapshot) -> Bool {
    window.lines.contains { !$0.plainText.allSatisfy(\.isWhitespace) }
  }

  // MARK: - Transcript rendering

  private var transcriptView: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 2) {
        if isLoading {
          ProgressView()
            .padding()
        }
        ForEach(session.transcript) { entry in
          StyledTextLineView(entry: entry)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 12)
    }
    // `.defaultScrollAnchor(.bottom)` only sets the initial offset and
    // bottom-aligns content shorter than the viewport. It does *not* keep
    // following once the transcript outgrows the viewport, so the explicit
    // re-pinning below drives the follow.
    .defaultScrollAnchor(.bottom)
    .scrollPosition($scrollPosition)
    // Track how far we are from the bottom so auto-follow only fires while the
    // user hasn't deliberately scrolled up. 24 pt of slack absorbs the jitter
    // from the input bar resizing the container on every turn.
    .onScrollGeometryChange(for: Bool.self) {
      $0.contentSize.height - $0.visibleRect.maxY < 24
    } action: { _, pinned in
      isPinnedToBottom = pinned
    }
    // New game output: follow it down. The pinned check reads the pre-growth
    // state because this fires before the appended rows are laid out.
    .onChange(of: session.transcript.count) { followBottomIfPinned() }
    // The input bar shows/hides every turn, resizing the scroll container and
    // knocking us off the bottom; re-pin when it does.
    .onChange(of: session.isAwaitingInput) { followBottomIfPinned() }
    // Status / secondary buffer panels appearing also resize the container.
    .onChange(of: session.statusWindows.count) { followBottomIfPinned() }
    .onChange(of: session.secondaryBufferWindows.count) { followBottomIfPinned() }
  }

  /// Scrolls the transcript back to its bottom edge, but only when the user was
  /// already parked there. Scrolling to the `.bottom` *edge* (not a measured
  /// trailing anchor) computes the true content bottom even under `LazyVStack`,
  /// where off-screen rows aren't laid out.
  private func followBottomIfPinned() {
    guard isPinnedToBottom else { return }
    withAnimation(.easeOut(duration: 0.2)) {
      scrollPosition.scrollTo(edge: .bottom)
    }
  }

  // MARK: - Secondary buffer windows (bottom panels)

  /// Non-primary buffer windows (e.g. Blue Lacuna's "Topics" window) shown as
  /// panels above the input bar, ordered by their on-screen `top`.
  @ViewBuilder
  private var bottomBufferPanels: some View {
    ForEach(session.secondaryBufferWindows) { window in
      BufferWindowPanelView(window: window)
    }
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

  private var lineInputBar: some View {
    HStack(spacing: 8) {
      Text(">")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gray)
      TextField("", text: $commandText)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gameText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($inputFocused)
        .onSubmit { dispatchTyped(commandText) }
        .submitLabel(.send)
        .accessibilityLabel("Enter command")
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
      TextField("y / n / 1 / …", text: $charInputText)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gameText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($inputFocused)
        .accessibilityLabel("Press a single key")
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
