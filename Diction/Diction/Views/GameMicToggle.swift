import SwiftUI

/// The game toolbar's microphone control. Voice commands are a locked feature,
/// free to try in a bundled game. Allowed: a tap toggles `voiceInput` (mirrored
/// by the Settings toggle; `GameView` drives the recognizer from it), and a
/// press-and-hold opens a menu to pick the microphone input — the corner chevron
/// advertises that menu. Locked: a disabled-looking mic that calls `onLocked`
/// (the paywall).
struct GameMicToggle: View {
  let coordinator: VoiceCoordinator
  /// Whether voice commands may run in this game (purchased, or a bundled game).
  let isAllowed: Bool
  let onLocked: () -> Void

  @AppStorage("voiceInput") private var voiceInput = false

  var body: some View {
    if isAllowed {
      Menu {
        Picker("Microphone", selection: micInputBinding) {
          Text("Automatic").tag(AudioInputChoice.automatic)
          ForEach(coordinator.audioRoute.availableInputs) { option in
            Text(option.name)
              .tag(AudioInputChoice.port(uid: option.id, portType: option.portType))
          }
        }
      } label: {
        micIcon
      } primaryAction: {
        voiceInput.toggle()
      }
      .accessibilityLabel(coordinator.isListening ? "Stop listening" : "Start listening")
      .accessibilityHint("Double-tap toggles listening; the menu chooses the microphone input.")
    } else {
      Button(action: onLocked) {
        Image(systemName: "mic.slash")
          .foregroundStyle(.gray)
      }
      .accessibilityLabel("Voice input locked")
      .accessibilityHint(
        "Opens the in-app purchase to play by speaking your commands. Free to try in All Things Devours."
      )
    }
  }

  /// The mic glyph with a corner chevron marking the press-and-hold input menu.
  private var micIcon: some View {
    Image(systemName: coordinator.isListening ? "mic.fill" : "mic.slash")
      .foregroundStyle(coordinator.isListening ? .blue : .gray)
      .overlay(alignment: .bottomTrailing) { MenuChevron() }
  }

  /// Binds the input picker to the route controller; selecting persists the choice
  /// and triggers the recognizer reconfigure.
  private var micInputBinding: Binding<AudioInputChoice> {
    Binding(
      get: { coordinator.audioRoute.choice },
      set: { coordinator.audioRoute.select($0) }
    )
  }
}
