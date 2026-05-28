import SwiftUI

struct GameView: View {
  let storyFile: StoryFile

  @State private var session = InterpreterSession()
  @State private var commandText = ""
  @State private var isVoiceMode = false
  @State private var isLoading = true
  @State private var loadError: String?
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
    .fullScreenCover(isPresented: $isVoiceMode) {
      VoiceOverlay(
        session: session,
        storyTitle: storyFile.title,
        isPresented: $isVoiceMode
      )
    }
  }

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
      Button {
        isVoiceMode = true
      } label: {
        Image(systemName: "mic.fill")
          .font(.title3)
          .foregroundStyle(.white)
          .frame(width: 36, height: 36)
          .background(Circle().fill(.blue))
      }
      .accessibilityLabel("Voice mode")
      .accessibilityHint("Opens full-screen voice input")
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(Color(white: 0.12))
  }

  private func sendCommand() {
    let command = commandText.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !command.isEmpty else { return }
    commandText = ""

    Task {
      await session.send(command)
    }
  }
}
