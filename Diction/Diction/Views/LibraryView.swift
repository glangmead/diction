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
  @State private var pendingImport: PendingStoryAdd?
  /// Which segment the Settings sheet shows. Reset to `.settings` for manual opens;
  /// set to `.about` only for the first-launch auto-present. Owned here and bound
  /// into `SettingsView` so the requested tab takes effect on every presentation.
  @State private var settingsTab: SettingsTab = .settings
  /// True only while the first-launch About sheet is up, so its dismissal — not a
  /// later manual Settings dismissal — is what records that About has been seen.
  @State private var autoShowingAbout = false
  /// Set once the user has seen the first-launch About screen; suppresses the
  /// auto-present on every later launch.
  @AppStorage("hasSeenAbout") private var hasSeenAbout = false

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
      .task {
        voiceWarmer.warmUpIfNeeded()
        // First launch ever: surface the About screen once. The flag is set when
        // that sheet is dismissed (see the Settings sheet's onDismiss).
        if !hasSeenAbout {
          settingsTab = .about
          autoShowingAbout = true
          showingSettings = true
        }
      }
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
            settingsTab = .settings
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
      .sheet(
        isPresented: $showingSettings,
        onDismiss: {
          // Only the first-launch About presentation records that About was seen;
          // dismissing a manually-opened Settings sheet must not set the flag.
          if autoShowingAbout {
            hasSeenAbout = true
            autoShowingAbout = false
          }
        },
        content: {
          SettingsView(selectedTab: $settingsTab)
        }
      )
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
      .confirmationDialog(
        "Already in your library",
        isPresented: Binding(
          get: { pendingImport != nil },
          set: { if !$0 { cancelPendingImport() } }
        ),
        presenting: pendingImport
      ) { pending in
        Button("Add a Copy") { commitPendingImport(pending) }
        Button("Cancel", role: .cancel) { cancelPendingImport() }
      } message: { pending in
        Text(
          "“\(pending.displayTitle)” is identical to “\(pending.existingTitle)”, "
            + "already in your library. Add another copy?"
        )
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
    StoryRowView(story: story, locked: locked, coverURL: fileManager.coverURL(for: story))
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

// MARK: - File import & dedup

extension LibraryView {
  /// Handles a file-importer result: validates the extension is one we know how to
  /// play, copies the picked file into a temp directory (while its security scope is
  /// live, since the dedup prompt is async and outlives the scope), then either adds
  /// it or — if it's byte-identical to a library game — stages a confirmation.
  func handleImport(_ result: Result<[URL], Error>) {
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
        let tempURL = try copyToTemp(url)
        if let existing = fileManager.contentDuplicate(of: tempURL) {
          pendingImport = PendingStoryAdd(
            sourceURL: tempURL,
            preferredName: nil,
            existingTitle: existing.title,
            displayTitle: url.deletingPathExtension().lastPathComponent
          )
        } else {
          save(tempURL: tempURL, preferredName: nil)
        }
      } catch {
        importError = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
      }
    }
  }

  /// Copy the picked file into a fresh temp directory, preserving its filename, so
  /// it survives past the security scope and a possible confirmation prompt.
  private func copyToTemp(_ url: URL) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = dir.appendingPathComponent(url.lastPathComponent)
    try FileManager.default.copyItem(at: url, to: dest)
    return dest
  }

  func commitPendingImport(_ pending: PendingStoryAdd) {
    save(tempURL: pending.sourceURL, preferredName: pending.preferredName)
    pendingImport = nil
  }

  func cancelPendingImport() {
    if let pending = pendingImport { removeTempDirectory(of: pending.sourceURL) }
    pendingImport = nil
  }

  private func save(tempURL: URL, preferredName: String?) {
    do {
      _ = try fileManager.addStory(from: tempURL, preferredName: preferredName)
    } catch {
      importError = "Couldn't import \(tempURL.lastPathComponent): \(error.localizedDescription)"
    }
    removeTempDirectory(of: tempURL)
  }

  private func removeTempDirectory(of fileURL: URL) {
    try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
  }
}
