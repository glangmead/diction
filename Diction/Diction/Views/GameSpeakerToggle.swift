import SwiftUI

/// The game toolbar's speaker (narration on/off) control. A tap toggles narration;
/// a press-and-hold opens a menu showing the current output and a "Choose Output…"
/// entry. The system route picker (`AVRoutePickerView`) can't live inside a `Menu`,
/// so that entry presents it in a popover. Matches the mic's tap/hold model; the
/// corner chevron advertises it.
struct GameSpeakerToggle: View {
  let coordinator: VoiceCoordinator

  @State private var showingOutputRoute = false

  var body: some View {
    Menu {
      Section(outputSectionTitle) {
        Button {
          showingOutputRoute = true
        } label: {
          Label("Choose Output…", systemImage: "airplayaudio")
        }
      }
    } label: {
      speakerIcon
    } primaryAction: {
      coordinator.setSpeaking(!coordinator.isSpeaking)
    }
    // Narration screeches through the Simulator's audio path, so the control is
    // disabled (and off) there; always enabled on a real device.
    .disabled(!coordinator.synthesizer.isAvailable)
    .accessibilityLabel(coordinator.isSpeaking ? "Mute narration" : "Unmute narration")
    .accessibilityHint("Double-tap toggles narration; the menu chooses the audio output.")
    .popover(isPresented: $showingOutputRoute) {
      OutputRoutePopover()
        .environment(coordinator.audioRoute)
        .presentationCompactAdaptation(.popover)
    }
  }

  /// The speaker glyph with a corner chevron marking the press-and-hold output menu.
  private var speakerIcon: some View {
    Image(systemName: coordinator.isSpeaking ? "speaker.wave.2.fill" : "speaker.slash")
      .foregroundStyle(coordinator.isSpeaking ? .blue : .gray)
      .overlay(alignment: .bottomTrailing) { MenuChevron() }
  }

  /// Header for the menu's output section — names the current device when known.
  private var outputSectionTitle: String {
    let name = coordinator.audioRoute.currentOutputName
    return name.isEmpty ? "Audio output" : "Output: \(name)"
  }
}
