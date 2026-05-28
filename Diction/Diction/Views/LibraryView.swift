import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
  @Bindable var fileManager: StoryFileManager
  @State private var showingIFDB = false
  @State private var showingSettings = false
  @State private var showingFileImporter = false
  @State private var importError: String?

  /// Story-file extensions we know how to play. The picker is permissive
  /// (allows `.data` and `.item`) because most IF extensions aren't
  /// registered system UTTypes; we validate against this set after pickup.
  private static let validExtensions: Set<String> = [
    "z3", "z5", "z8", "zblorb",
    "ulx", "gblorb", "blb", "blorb"
  ]

  var body: some View {
    NavigationStack {
      List(fileManager.stories) { story in
        NavigationLink(value: story) {
          storyRow(story)
        }
      }
      .navigationTitle("Library")
      .navigationDestination(for: StoryFile.self) { story in
        GameView(storyFile: story)
          .onAppear { fileManager.recordPlayed(story) }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            showingSettings = true
          } label: {
            Image(systemName: "gearshape")
          }
          .accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showingFileImporter = true
          } label: {
            Image(systemName: "folder.badge.plus")
          }
          .accessibilityLabel("Add from Files")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Browse IFDB") {
            showingIFDB = true
          }
        }
      }
      .sheet(isPresented: $showingIFDB) {
        IFDBBrowserView(fileManager: fileManager)
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
      }
      .fileImporter(
        isPresented: $showingFileImporter,
        allowedContentTypes: [.data, .item],
        allowsMultipleSelection: false
      ) { result in
        handleImport(result)
      }
      .alert(
        "Couldn't add game",
        isPresented: Binding(
          get: { importError != nil },
          set: { if !$0 { importError = nil } }
        )
      ) {
        Button("OK") { importError = nil }
      } message: {
        Text(importError ?? "")
      }
      .overlay {
        if fileManager.stories.isEmpty {
          ContentUnavailableView(
            "No Games",
            systemImage: "book.closed",
            description: Text(
              "Import story files or browse IFDB to get started."
            )
          )
        }
      }
    }
  }

  private func storyRow(_ story: StoryFile) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(story.title)
        .font(.headline)
      HStack(spacing: 8) {
        Text(story.format == .zMachine ? "Z-machine" : "Glulx")
          .font(.caption)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            Capsule()
              .fill(story.format == .zMachine ? .blue : .purple)
              .opacity(0.2)
          )
        Text(story.source.label)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let date = story.lastPlayed {
          Spacer()
          Text(date, style: .relative)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityDescription(for: story))
  }

  /// Handles a file-importer result: validates the extension is one we know
  /// how to play, then copies the file into Documents (where the rest of the
  /// app will pick it up on the next refresh). Manages the system-supplied
  /// security scope on the source URL.
  private func handleImport(_ result: Result<[URL], Error>) {
    switch result {
    case .failure(let error):
      importError = "File picker failed: \(error.localizedDescription)"
    case .success(let urls):
      guard let url = urls.first else { return }
      let ext = url.pathExtension.lowercased()
      guard Self.validExtensions.contains(ext) else {
        importError = """
        \(url.lastPathComponent) doesn't look like an interactive-fiction story file. \
        Supported formats: .z3, .z5, .z8, .zblorb, .ulx, .gblorb, .blorb, .blb.
        """
        return
      }
      let needsScope = url.startAccessingSecurityScopedResource()
      defer {
        if needsScope { url.stopAccessingSecurityScopedResource() }
      }
      do {
        _ = try fileManager.importStory(from: url)
      } catch {
        importError = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
      }
    }
  }

  private func accessibilityDescription(for story: StoryFile) -> String {
    var parts: [String] = [story.title]
    parts.append(story.format == .zMachine ? "Z-machine" : "Glulx")
    parts.append(story.source.label)
    if story.lastPlayed != nil {
      parts.append("recently played")
    }
    return parts.joined(separator: ", ")
  }
}
