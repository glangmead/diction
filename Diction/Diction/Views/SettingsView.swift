import SwiftUI
import AVFoundation

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage("speechRate") private var speechRate: Double = Double(
    AVSpeechUtteranceDefaultSpeechRate
  )
  @AppStorage("speechVoiceId") private var voiceId: String = ""

  private let voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice
    .speechVoices()
    .filter { $0.language.hasPrefix("en") }
    .sorted { $0.name < $1.name }

  var body: some View {
    NavigationStack {
      Form {
        Section("Speech") {
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
            .accessibilityValue(rateLabel)
          }

          Picker("Voice", selection: $voiceId) {
            Text("System Default").tag("")
            ForEach(voices, id: \.identifier) { voice in
              Text("\(voice.name) (\(voice.quality.label))")
                .tag(voice.identifier)
            }
          }
        }

        Section("About") {
          LabeledContent("Z-machine interpreter") {
            Text("Bocfel (MIT)").foregroundStyle(.secondary)
          }
          LabeledContent("Glulx interpreter") {
            Text("Glulxe (MIT)").foregroundStyle(.secondary)
          }
          LabeledContent("Glk implementation") {
            Text("RemGlk (MIT)").foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private var rateLabel: String {
    let normalized = (speechRate - Double(AVSpeechUtteranceMinimumSpeechRate))
      / Double(AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
    let percent = Int((normalized * 100).rounded())
    return "\(percent)%"
  }
}

extension AVSpeechSynthesisVoiceQuality {
  var label: String {
    switch self {
    case .default: "Default"
    case .enhanced: "Enhanced"
    case .premium: "Premium"
    @unknown default: "Unknown"
    }
  }
}
