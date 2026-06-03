import SwiftUI
import AVFoundation
import StoreKit
import UIKit

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(StoreManager.self) private var store
  @AppStorage("speechRate") private var speechRate: Double = Double(
    AVSpeechUtteranceDefaultSpeechRate
  )
  @AppStorage("speechVoiceId") private var voiceId: String = ""
  @AppStorage("wakeWord") private var wakeWord: String = "game"

  // Spike: neural Kokoro voice settings.
  @AppStorage("useKokoro") private var useKokoro: Bool = true
  @AppStorage("kokoroVoiceId") private var kokoroVoiceId: String = "af_heart"
  @AppStorage("kokoroEchoVoiceId") private var kokoroEchoVoiceId: String = "am_michael"

  // Flowing-text font (defaults must match StyledTextLineView).
  @AppStorage("readingTypeface") private var readingTypeface = ReadingTypeface.sansSerif.rawValue
  @AppStorage("readingTextSize") private var readingTextSize = ReadingTextSize.medium.rawValue

  /// Count of currently-installed Premium voices, used to surface whether
  /// the user has installed any of Apple's higher-quality voices.
  private let installedPremiumCount: Int = AVSpeechSynthesisVoice.speechVoices()
    .filter { $0.language.hasPrefix("en") && $0.quality == .premium }
    .count

  var body: some View {
    NavigationStack {
      Form {
        UnlockSettingsRow()
        kokoroSection
        speechSection
        readingTextSection
        moreVoicesSection
        aboutSection
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  // MARK: - Neural voice (Kokoro) section

  private var kokoroSection: some View {
    Section {
      Toggle("Use neural voice", isOn: $useKokoro)
        .accessibilityHint("When off, falls back to the system voice configured below.")

      if useKokoro {
        NavigationLink {
          KokoroVoicePickerView(title: "Game Voice", selectedVoiceID: $kokoroVoiceId)
        } label: {
          LabeledContent("Game voice") {
            Text(KokoroSpeechEngine.displayName(
              for: DemoPolicy.effectiveKokoroVoice(
                kokoroVoiceId, role: .game, fullVersion: store.isFullVersion)))
              .foregroundStyle(.secondary)
          }
        }
        NavigationLink {
          KokoroVoicePickerView(title: "Echo Voice", selectedVoiceID: $kokoroEchoVoiceId)
        } label: {
          LabeledContent("Command echo voice") {
            Text(KokoroSpeechEngine.displayName(
              for: DemoPolicy.effectiveKokoroVoice(
                kokoroEchoVoiceId, role: .echo, fullVersion: store.isFullVersion)))
              .foregroundStyle(.secondary)
          }
        }
      }
    } header: {
      Text("Neural Voice (Kokoro)")
    } footer: {
      Text(
        """
        On-device neural TTS. A different echo voice marks app replies as \
        distinct from the game's narration. Requires a recent device; the \
        simulator falls back to the system voice.
        """
      )
    }
  }

  // MARK: - Speech section

  private var speechSection: some View {
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

      NavigationLink {
        VoicePickerView(selectedVoiceId: $voiceId)
      } label: {
        LabeledContent("Voice") {
          Text(currentVoiceLabel)
            .foregroundStyle(.secondary)
        }
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
    }
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

  // MARK: - Reading text section

  private var readingTextSection: some View {
    Section {
      Picker("Typeface", selection: $readingTypeface) {
        ForEach(ReadingTypeface.allCases) { typeface in
          Text(typeface.label).tag(typeface.rawValue)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Text size")
          Spacer()
          Text(currentReadingSizeLabel)
            .foregroundStyle(.secondary)
            .font(.callout)
        }
        Slider(
          // Pure step↔Double projection; the Int step in @AppStorage stays the
          // source of truth for the five discrete sizes.
          value: Binding(
            get: { Double(readingTextSize) },
            set: { readingTextSize = Int($0.rounded()) }
          ),
          in: 0...Double(ReadingTextSize.allCases.count - 1),
          step: 1
        )
        .accessibilityLabel("Reading text size")
        .accessibilityValue(currentReadingSizeLabel)
      }
    } header: {
      Text("Reading Text")
    } footer: {
      Text(
        """
        Font for the scrolling story text. The status bar stays monospaced. \
        Size multiplies your device's Dynamic Type setting.
        """
      )
    }
  }

  private var currentReadingSizeLabel: String {
    (ReadingTextSize(rawValue: readingTextSize) ?? .medium).label
  }

  // MARK: - More voices section

  private var moreVoicesSection: some View {
    Section {
      LabeledContent("Premium voices installed") {
        Text("\(installedPremiumCount)")
          .foregroundStyle(.secondary)
      }

      Text(moreVoicesExplanation)
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
    } header: {
      Text("More Voices")
    } footer: {
      Text("iOS does not allow apps to install voices directly; the Settings app handles the download.")
    }
  }

  private var moreVoicesExplanation: String {
    """
    iOS includes higher-quality 'Enhanced' and 'Premium' voices that aren't \
    installed by default. To add them: open the Settings app, then go to \
    Accessibility → Spoken Content → Voices → English. Tap any voice marked \
    Enhanced or Premium to download it. Once installed, it will appear in \
    the Voice picker above.
    """
  }

  // MARK: - About

  private var aboutSection: some View {
    Section("About") {
      LabeledContent("Z-machine interpreter") {
        Text("Bocfel (MIT)").foregroundStyle(.secondary)
      }
      LabeledContent("Glulx interpreter") {
        Text("Glulxe (MIT)").foregroundStyle(.secondary)
      }
      LabeledContent("Glk implementation") {
        Text("RemGlk-rs (MIT)").foregroundStyle(.secondary)
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
