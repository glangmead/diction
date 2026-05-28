import SwiftUI

struct GameView: View {
  let storyFile: StoryFile

  @State private var session = InterpreterSession()
  @State private var commandText = ""
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
            styledTextView(entry)
              .id(entry.id)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
      }
      .onChange(of: session.transcript.count) {
        if let last = session.transcript.last {
          withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
    }
  }

  private func styledTextView(_ text: StyledText) -> some View {
    text.runs.reduce(Text("")) { result, run in
      result + styledRun(run)
    }
    .font(.system(.body, design: .monospaced))
    .foregroundStyle(Color(white: 0.92))
    .accessibilityLabel(text.plainText)
  }

  private func styledRun(_ run: StyledText.Run) -> Text {
    var text = Text(run.text)
    switch run.style {
    case .header, .subheader:
      text = text.bold()
    case .emphasized:
      text = text.italic()
    case .input:
      text = text.foregroundColor(.gray)
    case .alert, .note:
      text = text.foregroundColor(.orange)
    default:
      break
    }
    return text
  }

  // MARK: - Input bar

  private var inputBar: some View {
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
        .onSubmit { sendCommand() }
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

  private func sendCommand() {
    let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else { return }
    commandText = ""

    // Capture voice-mode state synchronously so toggling voice mode mid-
    // response doesn't leave the recognizer suspended.
    let voiceCoordinated = isVoiceMode
    if voiceCoordinated {
      recognizer.setExternallySuspended(true)
    }

    Task {
      let indexBefore = session.transcript.count
      await session.send(command)
      if voiceCoordinated {
        // RESTORE / RESTART clear the transcript and redraw — if the new
        // count is shorter than where we started, the response is the
        // entire fresh game state. Stay silent in that case; the user
        // can say "look" if they want to hear where they ended up.
        if session.transcript.count >= indexBefore {
          let responseEntries = session.transcript[indexBefore...]
            .filter { !$0.isUserInput }
          for entry in responseEntries {
            await synthesizer.speak(entry)
          }
        }
        recognizer.setExternallySuspended(false)
      }
    }
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
      commandText = trimmed
      sendCommand()
    }
    recognizer.startContinuous(contextualStrings: contextualStringsForRecognition())
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

  /// Composes the contextual-strings list for `SFSpeechRecognizer`:
  /// canonical IF terms first (so they survive truncation regardless of
  /// per-game dictionary size), then the game's extracted parser dict.
  /// Duplicates are dropped case-insensitively.
  private func contextualStringsForRecognition() -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    for word in IFCanonicalTerms.all where seen.insert(word.lowercased()).inserted {
      ordered.append(word)
    }
    for word in session.dictionary where seen.insert(word.lowercased()).inserted {
      ordered.append(word)
    }
    return ordered
  }
}
