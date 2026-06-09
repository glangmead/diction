import SwiftUI
import AVFoundation
import UIKit

/// Drill-down picker for the system (Apple) narration voice, grouped by language
/// (English first), each row showing its locale and quality. There is no "system
/// default" entry — every choice is an explicitly named voice, which is far less
/// confusing than a default that silently ignores the user's iOS voice settings.
/// When the user hasn't picked one, the best English voice is highlighted as the
/// effective selection (see `SystemVoiceCatalog.defaultIdentifier`).
struct VoicePickerView: View {
  @Binding var selectedVoiceId: String
  @Environment(\.dismiss) private var dismiss

  private let groupedVoices: [SystemVoiceGroup]
  private let defaultVoiceId: String?

  init(selectedVoiceId: Binding<String>) {
    self._selectedVoiceId = selectedVoiceId
    let installed = SystemVoiceCatalog.installed()
    self.groupedVoices = SystemVoiceCatalog.grouped(installed)
    self.defaultVoiceId = SystemVoiceCatalog.defaultIdentifier(from: installed)
  }

  /// The voice currently in effect: the explicit choice, or the resolved default
  /// when none has been made. Drives the checkmark.
  private var effectiveSelectedId: String {
    selectedVoiceId.isEmpty ? (defaultVoiceId ?? "") : selectedVoiceId
  }

  var body: some View {
    List {
      Section {
        Text(Self.explanation)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
        } label: {
          Label("Open Settings", systemImage: "gear")
        }
      }

      ForEach(groupedVoices) { group in
        Section(group.displayName) {
          ForEach(group.voices, id: \.identifier) { voice in
            let isSelected = voice.identifier == effectiveSelectedId
            Button {
              selectedVoiceId = voice.identifier
              dismiss()
            } label: {
              voiceRowLabel(primary: SystemVoiceCatalog.label(for: voice), isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
          }
        }
      }
    }
    .navigationTitle("Accessibility Voice")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func voiceRowLabel(primary: String, isSelected: Bool) -> some View {
    HStack {
      Text(primary)
        .foregroundStyle(.primary)
      Spacer()
      if isSelected {
        Image(systemName: "checkmark")
          .foregroundStyle(.tint)
          .accessibilityHidden(true)   // selection is conveyed by the .isSelected trait
      }
    }
    .contentShape(Rectangle())
  }

  private static let explanation = """
  Diction narrates in English, French, and Spanish. iOS includes higher-quality \
  Enhanced and Premium voices for these that aren't installed by default. To add one, \
  open Settings → Accessibility → Spoken Content → Voices, download a voice, then \
  return here and pick it. A newly installed voice may not appear until you reopen \
  Diction. Siri voices can't be used by apps, so they won't show up here.
  """
}
