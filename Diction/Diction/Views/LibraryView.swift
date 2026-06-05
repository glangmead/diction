import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
  @Bindable var fileManager: StoryFileManager
  @Environment(VoiceWarmer.self) private var voiceWarmer
  @Environment(StoreManager.self) private var store
  @State private var showingIFDB = false
  @State private var showingSettings = false
  @State private var showingFileImporter = false
  @State private var showingPaywall = false
  @State private var importError: String?
  @State private var deleteError: String?

  var body: some View {
    NavigationStack {
      List {
        ForEach(fileManager.stories) { story in
          row(for: story)
            .swipeActions(edge: .trailing) {
              if story.source != .bundled {
                Button(role: .destructive) {
                  delete(story)
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
            }
        }
        if store.entitlementResolved && !store.isFullVersion {
          Section {
            LibraryUnlockRow { showingPaywall = true }
          }
        }
      }
      .navigationTitle("Library")
      // A large title collapses to an empty band under a top `safeAreaInset`,
      // stranding the banner below it; an inline title coexists cleanly. (A
      // display mode switched dynamically on readiness rendered unreliably, so
      // it's inline unconditionally.)
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .top, spacing: 0) {
        if voiceWarmer.readiness == .preparing {
          voicePreparingBanner
        }
      }
      .animation(.default, value: voiceWarmer.readiness)
      .task { voiceWarmer.warmUpIfNeeded() }
      .onChange(of: voiceWarmer.readiness) { old, new in
        if old == .preparing, new == .ready {
          AccessibilityNotification.Announcement("Narration voice ready").post()
        }
      }
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
            // The nav-bar toolbar collapses a Label/systemImage button to
            // icon-only; a custom HStack label renders both icon and title.
            HStack(spacing: 4) {
              Image(systemName: "folder.badge.plus")
              Text("Add")
            }
          }
          .accessibilityLabel("Add file")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showingIFDB = true
          } label: {
            // The nav-bar toolbar collapses a Label/systemImage button to
            // icon-only; a custom HStack label renders both icon and title.
            HStack(spacing: 4) {
              Image(systemName: "magnifyingglass")
              Text("Find")
            }
          }
        }
      }
      .sheet(isPresented: $showingIFDB) {
        IFDBBrowserView(fileManager: fileManager)
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
      }
      .sheet(isPresented: $showingPaywall) {
        PaywallView()
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
      .alert(
        "Couldn't delete game",
        isPresented: Binding(
          get: { deleteError != nil },
          set: { if !$0 { deleteError = nil } }
        )
      ) {
        Button("OK") { deleteError = nil }
      } message: {
        Text(deleteError ?? "")
      }
      .overlay {
        if fileManager.stories.isEmpty {
          ContentUnavailableView(
            "No Games",
            systemImage: "book.closed",
            description: Text(
              "Import story files or search IFDB to get started."
            )
          )
        }
      }
    }
  }

  /// Inform-only, full-width banner shown only while the neural voice is loading
  /// (in practice, the first launch after an update — the model's ANE compile is
  /// cached thereafter). It slides away the moment the voice is ready; nothing is
  /// shown for the system voice or when neural is unavailable, since there's no
  /// load to wait on. The `.preparing`-only `if` means `safeAreaInset` reserves
  /// no space otherwise.
  private var voicePreparingBanner: some View {
    HStack(spacing: 10) {
      ProgressView()
        .controlSize(.small)
      Text("Preparing the neural voice for narration…")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.bar)
    .overlay(alignment: .bottom) { Divider() }
    .transition(.move(edge: .top).combined(with: .opacity))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Preparing narration voice")
  }

  /// Locked (non-bundled in demo) rows open the paywall instead of the game;
  /// playable rows navigate. Locks only show once entitlement has resolved, so a
  /// returning owner never sees a flash on cold launch.
  @ViewBuilder
  private func row(for story: StoryFile) -> some View {
    if isLocked(story) {
      Button {
        showingPaywall = true
      } label: {
        storyRow(story, locked: true)
      }
      .buttonStyle(.plain)
    } else {
      NavigationLink(value: story) {
        storyRow(story, locked: false)
      }
    }
  }

  private func isLocked(_ story: StoryFile) -> Bool {
    store.entitlementResolved
      && !DemoPolicy.isPlayable(story, fullVersion: store.isFullVersion)
  }

  private func storyRow(_ story: StoryFile, locked: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(story.title)
          .font(.headline)
        Spacer(minLength: 8)
        if locked {
          Image(systemName: "lock.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
      }
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
      }
      LibraryStatusPreview(url: story.url, lastPlayed: story.lastPlayed)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityDescription(for: story, locked: locked))
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
      // The picker allows `.data`/`.item` (most IF extensions aren't registered
      // UTTypes), so validate the extension here against the formats we play.
      guard StoryFile.supportedExtensions.contains(ext) else {
        importError = """
        \(url.lastPathComponent) doesn't look like an interactive-fiction story file. \
        Supported formats: Z-machine .z3/.z5/.z8, Glulx .ulx, and Blorb (.zblorb, .gblorb, .blorb, .blb).
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

  private func accessibilityDescription(for story: StoryFile, locked: Bool) -> String {
    var parts: [String] = [story.title]
    parts.append(story.format == .zMachine ? "Z-machine" : "Glulx")
    parts.append(story.source.label)
    if story.lastPlayed != nil {
      parts.append("recently played")
    }
    if locked {
      parts.append("locked, double tap to unlock")
    }
    return parts.joined(separator: ", ")
  }
}

// MARK: - Deletion helper

extension LibraryView {
  /// Removes a swiped story, surfacing any failure (e.g. the file vanished
  /// out from under us) in the delete alert rather than silently.
  func delete(_ story: StoryFile) {
    do {
      try fileManager.deleteStory(story)
    } catch {
      deleteError = "Couldn't delete \(story.title). \(error.localizedDescription)"
    }
  }
}
