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
  /// "Speak back my commands" — when on (default), the app reads each command you enter
  /// back to you before narrating the game's reply. Gates the readback in
  /// `VoiceCoordinator.sendToGame`.
  @AppStorage("repeatCommands") private var repeatCommands = true
  /// Diagnostic: log the ASR post-processing (heard words, per-word candidates,
  /// recovery/correction decisions) to the console.
#if DEBUG
  @AppStorage("logSpeechInterventions") private var logSpeechInterventions = false
#endif
  /// The paywall presented by the gated voice toggles. Owned here, on the stable
  /// NavigationStack content, rather than on `VoiceSettingsSection`'s `Section` —
  /// a sheet anchored to a `Section` is torn down on re-render and takes the
  /// Settings sheet with it.
  @State private var showingPaywall = false

  /// In-flight state for the diagnostics export, and the file it produced (revealed
  /// as a share row once ready). Voice issues are intermittent, so the user
  /// reproduces, then exports a recent on-device activity log to send to support.
  @State private var isExportingDiagnostics = false
  @State private var exportedLogURL: URL?

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
      .sheet(isPresented: $showingPaywall) {
        PaywallView()
      }
    }
  }

  private var settingsForm: some View {
    Form {
      UnlockSettingsRow()
      VoiceSettingsSection(onRequestUnlock: { showingPaywall = true })
      readingTextSection
      exportDiagnosticsSection
#if DEBUG
      diagnosticsSection
#endif
    }
  }

  // MARK: - Diagnostics

  /// Release-visible: produce a recent activity log and share it (Mail / AirDrop /
  /// Files). The file is generated on demand so it captures the latest run, then
  /// revealed as a `ShareLink` row. See `DiagnosticsExport`.
  private var exportDiagnosticsSection: some View {
    Section {
      Button {
        isExportingDiagnostics = true
        Task {
          defer { isExportingDiagnostics = false }
          let url = try? await DiagnosticsExport.makeLogFile()
          exportedLogURL = url
          // The share row appears asynchronously below; announce it so a VoiceOver
          // user knows the export finished and where to go next.
          AccessibilityNotification.Announcement(
            url == nil ? "Couldn't prepare the activity log." : "Activity log ready to share."
          ).post()
        }
      } label: {
        HStack {
          Text("Export Diagnostics")
          Spacer()
          if isExportingDiagnostics { ProgressView() }
        }
      }
      .disabled(isExportingDiagnostics)
      .accessibilityValue(isExportingDiagnostics ? "Preparing" : "")
      .accessibilityHint("Prepares a recent activity log you can share with support.")
      if let exportedLogURL {
        ShareLink("Share diagnostics log", item: exportedLogURL)
      }
    } header: {
      Text("Diagnostics")
    } footer: {
      Text("If something isn't working right (a spoken command ignored, narration silent, etc.), "
        + "reproduce it, then export a recent activity log to send to support.")
    }
  }

#if DEBUG
  private var diagnosticsSection: some View {
    Section {
      Toggle("Log speech interventions", isOn: $logSpeechInterventions)
    } header: {
      Text("Developer logging")
    } footer: {
      Text("Streams verbose ASR tracing — heard words, each word's candidates, and "
        + "recovery/correction decisions — to the live console. Not included in "
        + "exported diagnostics.")
    }
  }
#endif

  // MARK: - Reading text section

  private var readingTextSection: some View {
    Section {
      Toggle("Speak back my commands", isOn: $repeatCommands)
        .accessibilityHint("Reads each command you enter back to you before the game's reply.")

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

}
