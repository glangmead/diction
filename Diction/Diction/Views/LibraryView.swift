import SwiftUI

struct LibraryView: View {
  @Bindable var fileManager: StoryFileManager
  @State private var showingIFDB = false
  @State private var showingSettings = false

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
