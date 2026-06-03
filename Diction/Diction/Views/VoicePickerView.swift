import SwiftUI
import AVFoundation

/// Drill-down voice picker grouped by quality (Premium first), with locale
/// labels so the user can pick an accent. Lives in its own view so the
/// list scrolls comfortably even when many voices are installed.
struct VoicePickerView: View {
  @Binding var selectedVoiceId: String
  @Environment(\.dismiss) private var dismiss

  private let groupedVoices: [VoiceGroup]

  init(selectedVoiceId: Binding<String>) {
    self._selectedVoiceId = selectedVoiceId
    let englishVoices = AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix("en") }
    let byQuality = Dictionary(grouping: englishVoices, by: \.quality)
    // Premium first so the highest-quality options are easiest to find.
    self.groupedVoices = [
      AVSpeechSynthesisVoiceQuality.premium,
      .enhanced,
      .default
    ].compactMap { quality in
      guard let voices = byQuality[quality], !voices.isEmpty else { return nil }
      return VoiceGroup(
        quality: quality,
        voices: voices.sorted { $0.name < $1.name }
      )
    }
  }

  var body: some View {
    List {
      Section {
        Button {
          selectedVoiceId = ""
          dismiss()
        } label: {
          voiceRowLabel(
            primary: "System Default",
            secondary: "Whatever iOS picks for your region",
            isSelected: selectedVoiceId.isEmpty
          )
        }
        .buttonStyle(.plain)
      }

      ForEach(groupedVoices) { group in
        Section(group.quality.label) {
          ForEach(group.voices, id: \.identifier) { voice in
            Button {
              selectedVoiceId = voice.identifier
              dismiss()
            } label: {
              voiceRowLabel(
                primary: voice.name,
                secondary: VoicePickerView.localeName(voice.language),
                isSelected: voice.identifier == selectedVoiceId
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .navigationTitle("Voice")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func voiceRowLabel(primary: String, secondary: String, isSelected: Bool) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(primary)
          .foregroundStyle(.primary)
        Text(secondary)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if isSelected {
        Image(systemName: "checkmark")
          .foregroundStyle(.tint)
      }
    }
    .contentShape(Rectangle())
  }

  /// Localized display name for a BCP-47 language tag, e.g. "en-AU" →
  /// "English (Australia)". Falls back to the raw tag if the system can't
  /// produce a localized name.
  private static func localeName(_ tag: String) -> String {
    Locale.current.localizedString(forIdentifier: tag) ?? tag
  }

  private struct VoiceGroup: Identifiable {
    let quality: AVSpeechSynthesisVoiceQuality
    let voices: [AVSpeechSynthesisVoice]
    var id: Int { quality.rawValue }
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
