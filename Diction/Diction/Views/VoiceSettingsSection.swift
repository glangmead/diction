import SwiftUI
import AVFoundation

/// The unified "Voice" settings group: the neural-voice toggle and picker, the
/// system "accessibility" voice picker, the shared speech rate, and the wake
/// word. The two voice engines are presented in parallel so they read the same.
struct VoiceSettingsSection: View {
  /// Asks the presenter (SettingsView) to show the paywall. The sheet is owned
  /// up there on stable content, not anchored to this `Section` — see SettingsView.
  let onRequestUnlock: () -> Void

  @Environment(StoreManager.self) private var store
  // Both voice features default off — they're the paid unlock. A free user
  // narrates through the accessibility voice and types commands.
  @AppStorage("useKokoro") private var useKokoro: Bool = false
  @AppStorage("voiceInput") private var voiceInput: Bool = false
  @AppStorage("kokoroVoiceId") private var kokoroVoiceId: String = "af_heart"
  @AppStorage("speechVoiceId") private var voiceId: String = ""
  @AppStorage("speechRate") private var speechRate: Double = Double(
    AVSpeechUtteranceDefaultSpeechRate
  )
  @AppStorage("wakeWord") private var wakeWord: String = "game"

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        gatedToggle(
          "Use neural voice",
          isOn: $useKokoro,
          hint: "When off, narration uses the accessibility voice below."
        )
        // Neural inference leans on the ANE; on pre-iOS 26 systems (older
        // silicon, less RAM) cold-load and synthesis can drag. A newer OS
        // implies newer hardware, so the caveat only earns its place below 26.
        if #unavailable(iOS 26) {
          Text("Neural voices may perform poorly on older devices.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      // Always reachable, even when neural is locked or off, so anyone can open
      // it and audition every voice. The chosen voice narrates only once neural
      // is unlocked and turned on.
      NavigationLink {
        KokoroVoicePickerView(title: "Neural Voice", selectedVoiceID: $kokoroVoiceId)
      } label: {
        LabeledContent("Neural voice") {
          Text(KokoroSpeechEngine.displayName(for: kokoroVoiceId))
            .foregroundStyle(.secondary)
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

      gatedToggle(
        "Play using my voice",
        isOn: $voiceInput,
        hint: "Speak your commands instead of typing."
      )

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
    }
  }

  /// A toggle for a paid voice feature. When unlocked it's a normal `Toggle`;
  /// while locked it's a row with a lock that opens the paywall instead of
  /// flipping — "show a paywall if the user tries to turn it on".
  @ViewBuilder
  private func gatedToggle(_ title: String, isOn: Binding<Bool>, hint: String) -> some View {
    if store.isFullVersion {
      Toggle(title, isOn: isOn)
        .accessibilityHint(hint)
    } else {
      Button {
        onRequestUnlock()
      } label: {
        LabeledContent {
          Image(systemName: "lock.fill")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        } label: {
          Text(title)
            .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      // Title stays the visible-text label (so Voice Control's "tap <name>"
      // works); the lock state is a value, not folded into the label.
      .accessibilityValue("Locked")
      .accessibilityHint("Opens the in-app purchase to unlock this feature.")
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
    // An empty selection means "use the resolved default" — show that voice's name,
    // not a "System Default" entry the user can't reason about. See VoicePickerView.
    let installed = SystemVoiceCatalog.installed()
    let resolvedId = voiceId.isEmpty ? SystemVoiceCatalog.defaultIdentifier(from: installed) : voiceId
    guard let resolvedId,
          let voice = installed.first(where: { $0.identifier == resolvedId }) else {
      return "—"
    }
    return SystemVoiceCatalog.label(for: voice)
  }
}
