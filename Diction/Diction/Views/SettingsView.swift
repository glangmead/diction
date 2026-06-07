import SwiftUI
import AVFoundation
import UIKit

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss

  /// Which segment is showing. Owned by the presenter (a `@Binding`, not seeded
  /// `@State`) so the first-launch presentation can reliably open on About while
  /// every manual open lands on Settings — init-seeded `@State` captures only the
  /// first render's value and would ignore a later change to the requested tab.
  @Binding var selectedTab: SettingsTab

  // Flowing-text font (defaults must match GameView's reading settings).
  @AppStorage("readingTypeface") private var readingTypeface = ReadingTypeface.sansSerif.rawValue
  @AppStorage("readingTextSize") private var readingTextSize = ReadingTextSize.medium.rawValue
  /// Diagnostic: log the ASR post-processing (heard words, per-word candidates,
  /// recovery/correction decisions) to the console.
  @AppStorage("logSpeechInterventions") private var logSpeechInterventions = false

  /// Count of currently-installed Premium voices, used to surface whether
  /// the user has installed any of Apple's higher-quality voices.
  private let installedPremiumCount: Int = AVSpeechSynthesisVoice.speechVoices()
    .filter { $0.language.hasPrefix("en") && $0.quality == .premium }
    .count

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker("Section", selection: $selectedTab) {
          ForEach(SettingsTab.allCases) { tab in
            Text(tab.label).tag(tab)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)

        switch selectedTab {
        case .settings: settingsForm
        case .about: AboutPane()
        }
      }
      .navigationTitle(selectedTab.label)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private var settingsForm: some View {
    Form {
      UnlockSettingsRow()
      VoiceSettingsSection()
      accessibilityVoicesSection
      readingTextSection
      diagnosticsSection
    }
  }

  // MARK: - Diagnostics

  private var diagnosticsSection: some View {
    Section {
      Toggle("Log speech interventions", isOn: $logSpeechInterventions)
    } header: {
      Text("Diagnostics")
    } footer: {
      Text("Writes ASR recovery details — heard words, each word's candidates, and "
        + "recovery/correction decisions — to the console.")
    }
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

  // MARK: - About Accessibility Voices section

  private var accessibilityVoicesSection: some View {
    Section {
      LabeledContent("Premium voices installed") {
        Text("\(installedPremiumCount)")
          .foregroundStyle(.secondary)
      }

      Text(accessibilityVoicesExplanation)
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
      Text("About Accessibility Voices")
    } footer: {
      Text("iOS does not allow apps to install voices directly; the Settings app handles the download.")
    }
  }

  private var accessibilityVoicesExplanation: String {
    """
    iOS includes higher-quality 'Enhanced' and 'Premium' voices that aren't \
    installed by default. To add them: open the Settings app, then go to \
    Accessibility → Spoken Content → Voices → English. Tap any voice marked \
    Enhanced or Premium to download it. Once installed, it will appear in \
    the Accessibility voice picker above.
    """
  }
}
