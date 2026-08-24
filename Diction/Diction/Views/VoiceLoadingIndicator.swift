import SwiftUI

/// Toolbar indicator shown while the neural narration voice loads (the model
/// cold-start can take ~15 s). Collapses to nothing once the voice is ready,
/// fails to load, or when the neural path is off.
struct VoiceLoadingIndicator: View {
  let synthesizer: SpeechSynthesizer

  var body: some View {
    if synthesizer.isPreparingVoice {
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
}
