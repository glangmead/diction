import SwiftUI
import AVFoundation

/// The unified "Voice" settings group: the neural-voice toggle and picker, the
/// system "accessibility" voice picker, the shared speech rate, and the wake
/// word. The two voice engines are presented in parallel so they read the same.
struct VoiceSettingsSection: View {
  @Environment(StoreManager.self) private var store
  @AppStorage("useKokoro") private var useKokoro: Bool = true
  @AppStorage("kokoroVoiceId") private var kokoroVoiceId: String = "af_heart"
  @AppStorage("speechVoiceId") private var voiceId: String = ""
  @AppStorage("speechRate") private var speechRate: Double = Double(
    AVSpeechUtteranceDefaultSpeechRate
  )
  @AppStorage("wakeWord") private var wakeWord: String = "game"

  var body: some View {
    Section {
      Toggle("Use neural voice", isOn: $useKokoro)
        .accessibilityHint("When off, narration uses the accessibility voice below.")

      if useKokoro {
        NavigationLink {
          KokoroVoicePickerView(title: "Neural Voice", selectedVoiceID: $kokoroVoiceId)
        } label: {
          LabeledContent("Neural voice") {
            Text(KokoroSpeechEngine.displayName(
              for: DemoPolicy.effectiveKokoroVoice(kokoroVoiceId, fullVersion: store.isFullVersion)))
              .foregroundStyle(.secondary)
          }
        }
      }

      NavigationLink {
        VoicePickerView(selectedVoiceId: $voiceId)
      } label: {
        LabeledContent("Accessibility voice") {
          Text(currentVoiceLabel)
            .foregroundStyle(.secondary)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Rate")
          Spacer()
          Text(rateLabel)
            .foregroundStyle(.secondary)
            .font(.callout.monospacedDigit())
        }
        Slider(
          value: $speechRate,
          in: Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate),
          step: 0.05
        )
        .accessibilityLabel("Speech rate")
        .accessibilityValue(rateAccessibilityValue)
      }

      VStack(alignment: .leading, spacing: 8) {
        LabeledContent("Wake word") {
          TextField("game", text: $wakeWord)
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .accessibilityLabel("Wake word")
        }
        Text(wakeWordExplanation)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    } header: {
      Text("Voice")
    } footer: {
      Text(
        """
        Neural voice is on-device TTS (recent devices; the simulator uses the \
        accessibility voice). The accessibility voice is iOS's built-in speech, \
        used when the neural voice is off or unavailable.
        """
      )
    }
  }

  /// The shared speech rate as the speed multiplier both engines use — 1.0× at
  /// the slider's centre, faster to the right, slower to the left.
  private var rateLabel: String {
    String(format: "%.1f×", KokoroSpeechEngine.speed(forStoredRate: Float(speechRate)))
  }

  private var rateAccessibilityValue: String {
    String(format: "%.1f times normal speed",
           KokoroSpeechEngine.speed(forStoredRate: Float(speechRate)))
  }

  private var wakeWordExplanation: String {
    let example = wakeWord.isEmpty ? "game" : wakeWord
    return """
    Say this before a command to talk to the app instead of the game — \
    e.g. “\(example), stop”. Short, common, distinct words are recognized best.
    """
  }

  private var currentVoiceLabel: String {
    if voiceId.isEmpty { return "System Default" }
    guard let voice = AVSpeechSynthesisVoice(identifier: voiceId) else {
      return "System Default"
    }
    return "\(voice.name) (\(voice.quality.label))"
  }
}
