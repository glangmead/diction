import SwiftUI

struct GameView: View {
  let storyFile: StoryFile

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
      ToolbarItem(placement: .topBarLeading) { settingsButton }
      ToolbarItem(placement: .topBarTrailing) { micToggle }
      ToolbarItem(placement: .topBarTrailing) { speakerToggle }
    }
    .sheet(isPresented: $showingSettings) {
      SettingsView()
    }
    .task {
      coordinator.attach(session: session)
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
          // Zero-height anchor at the true end of the LazyVStack.
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
        .onSubmit { dispatchTyped(commandText) }
        .submitLabel(.send)
        .accessibilityLabel("Enter command")
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(Color(white: 0.12))
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
        .foregroundStyle(Color(white: 0.9))
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
    .background(Color(white: 0.12))
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
