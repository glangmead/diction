import SwiftUI
import UniformTypeIdentifiers

@main
struct DictionApp: App {
  @State private var fileManager = StoryFileManager()
  @State private var importError: String?

  var body: some Scene {
    WindowGroup {
      LibraryView(fileManager: fileManager)
        .onOpenURL(perform: handleOpen)
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
