import SwiftUI

struct VoiceOverlay: View {
  let session: InterpreterSession
  let storyTitle: String
  @Binding var isPresented: Bool

  @State private var recognizer = SpeechRecognizer()
  @State private var normalizer = CommandNormalizer()
  @State private var synthesizer = SpeechSynthesizer()
  @State private var lastCommand = ""
  @State private var isAuthorized = false
  @State private var isProcessing = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      header
      Spacer(minLength: 0)
      outputDisplay
      Spacer(minLength: 0)
      micButton
      dismissButton
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(white: 0.05))
    .foregroundStyle(.white)
    .task {
      isAuthorized = await recognizer.requestAuthorization()
      normalizer.configure(context: session)
      if let lastOutput = session.transcript.last {
        await synthesizer.speak(lastOutput)
      }
    }
    .onDisappear {
      synthesizer.stop()
      if recognizer.isListening {
        _ = recognizer.stopListening()
      }
    }
  }

  private var header: some View {
    Text(storyTitle)
      .font(.subheadline)
      .foregroundStyle(.gray)
      .padding(.top, 24)
  }

  private var outputDisplay: some View {
    VStack(spacing: 16) {
      if let lastOutput = session.transcript.last {
        ScrollView {
          Text(lastOutput.plainText.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Color(white: 0.85))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
        }
        .frame(maxHeight: 220)
      }

      if !lastCommand.isEmpty {
        Text("> \(lastCommand)")
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(Color(red: 0.83, green: 0.68, blue: 0.10))
          .padding(.horizontal, 24)
          .accessibilityLabel("Sent command: \(lastCommand)")
      }

      if recognizer.isListening, !recognizer.transcription.isEmpty {
        Text(recognizer.transcription)
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(.blue)
          .italic()
          .padding(.horizontal, 24)
          .accessibilityLabel("Hearing: \(recognizer.transcription)")
      }
    }
  }

  private var micButton: some View {
    VStack(spacing: 8) {
      Circle()
        .fill(micFillColor)
        .frame(width: 96, height: 96)
        .overlay {
          Image(systemName: "mic.fill")
            .font(.system(size: 36))
            .foregroundStyle(.white)
        }
        .shadow(color: micFillColor.opacity(0.4), radius: 20)
        .scaleEffect(recognizer.isListening ? 1.1 : 1.0)
        .animation(
          reduceMotion ? nil : .easeInOut(duration: 0.2),
          value: recognizer.isListening
        )
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { _ in
              if !recognizer.isListening && !isProcessing && isAuthorized {
                startListening()
              }
            }
            .onEnded { _ in
              if recognizer.isListening {
                stopAndProcess()
              }
            }
        )
        .accessibilityLabel(recognizer.isListening ? "Stop and send command" : "Speak a command")
        .accessibilityHint("Double-tap to toggle listening")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
          // VoiceOver / Switch Control reach the press-and-hold gesture via
          // this action: single tap toggles listening on/off.
          if recognizer.isListening {
            stopAndProcess()
          } else if !isProcessing && isAuthorized {
            startListening()
          }
        }

      Text(micLabel)
        .font(.caption)
        .foregroundStyle(.gray)
    }
    .padding(.bottom, 24)
  }

  private var micFillColor: Color {
    if !isAuthorized {
      return .gray
    }
    return recognizer.isListening ? .red : .blue
  }

  private var micLabel: String {
    if !isAuthorized {
      return "Microphone access denied"
    }
    if isProcessing {
      return "Processing…"
    }
    return recognizer.isListening ? "Release to send" : "Hold to speak"
  }

  private var dismissButton: some View {
    Button {
      synthesizer.stop()
      isPresented = false
    } label: {
      Label("Exit voice mode", systemImage: "chevron.down")
        .font(.caption)
        .foregroundStyle(.gray)
    }
    .padding(.bottom, 16)
    .accessibilityLabel("Exit voice mode")
  }

  private func startListening() {
    synthesizer.stop()
    do {
      try recognizer.startListening(contextualStrings: session.contextualStrings)
    } catch {
      // Surfaced via recognizer.errorMessage.
    }
  }

  private func stopAndProcess() {
    let speech = recognizer.stopListening()
    let trimmed = speech.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    isProcessing = true
    Task {
      let normalized = await normalizer.normalize(trimmed, context: session)
      lastCommand = normalized.command

      // Echo the normalized command back to the user so they know what
      // was actually sent.
      await synthesizer.speakCommandEcho(normalized.command)

      await session.send(normalized.command)

      if let newOutput = session.transcript.last {
        await synthesizer.speak(newOutput)
      }
      isProcessing = false
    }
  }
}
