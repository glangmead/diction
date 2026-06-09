import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct DictionApp: App {
  @State private var fileManager = StoryFileManager()
  @State private var voiceWarmer = VoiceWarmer()
  @State private var store = StoreManager()
  @State private var speechProfiles = SpeechProfileStore()
  @State private var importError: String?
  /// "Keep device awake" (Voice settings, default on). When on, the app holds the
  /// idle timer off while it's the active scene so the screen doesn't dim and lock
  /// mid-read or during a hands-free voice session.
  @AppStorage("keepDeviceAwake") private var keepDeviceAwake = true
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      LibraryView(fileManager: fileManager)
        .environment(voiceWarmer)
        .environment(store)
        .environment(speechProfiles)
        .onOpenURL(perform: handleOpen)
        .task { applyIdleTimer() }
        .onChange(of: keepDeviceAwake) { applyIdleTimer() }
        .onChange(of: scenePhase) { applyIdleTimer() }
        .alert(
          "Couldn't import file",
          isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
          )
        ) {
          Button("OK", role: .cancel) { importError = nil }
        } message: {
          Text(importError ?? "")
        }
    }
  }

  /// Apply "Keep device awake": disable the idle timer only while the app is the
  /// active scene and the setting is on. iOS clears the flag when backgrounded, so
  /// the scenePhase change re-applies it on return to the foreground.
  @MainActor
  private func applyIdleTimer() {
    UIApplication.shared.isIdleTimerDisabled = keepDeviceAwake && scenePhase == .active
  }

  private func handleOpen(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    do {
      try fileManager.importStory(from: url)
    } catch {
      importError = error.localizedDescription
    }
  }
}
