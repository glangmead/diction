import SwiftUI

struct IFDBBrowserView: View {
  var fileManager: StoryFileManager
  @Environment(\.dismiss) private var dismiss

  @State private var searchText = ""
  @State private var results: [IFDBSearchResult] = []
  @State private var isSearching = false
  @State private var downloading: Set<String> = []
  /// TUIDs whose download network request has succeeded this session — the row
  /// shows a checkmark instead of the Download button. View-local, so it resets
  /// when the browser is torn down.
  @State private var downloaded: Set<String> = []
  @State private var errorMessage: String?
  @State private var downloadError: String?
  @State private var showingDownloadError = false
  @State private var pendingAdd: PendingStoryAdd?
  @State private var selected: IFDBSearchResult?
  private let client = IFDBClient()

  /// Side padding for the devsys capsule — at least its corner radius (half the
  /// height) so the text clears the rounded ends; scales with the caption font.
  @ScaledMetric(relativeTo: .caption) private var chipHorizontalPadding: CGFloat = 10

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Search IFDB")
        .navigationDestination(item: $selected) { result in
          IFDBGameDetailView(
            tuid: result.tuid,
            fallbackTitle: result.title,
            fileManager: fileManager
          )
        }
        .searchable(text: $searchText, prompt: "Search IFDB")
        .onSubmit(of: .search) { performSearch() }
        .onChange(of: searchText) { _, newValue in
          // Clearing the field returns the user to the curated landing list.
          if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = []
            errorMessage = nil
          }
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
          }
        }
        .alert(
          "Download failed",
          isPresented: $showingDownloadError,
          presenting: downloadError
        ) { _ in
        } message: { message in
          Text(message)
        }
        .confirmationDialog(
          "Already in your library",
          isPresented: Binding(
            get: { pendingAdd != nil },
            set: { if !$0 { cancelPendingAdd() } }
          ),
          presenting: pendingAdd
        ) { pending in
          Button("Add a Copy") { commitPendingAdd(pending) }
          Button("Cancel", role: .cancel) { cancelPendingAdd() }
        } message: { pending in
          Text(
            "“\(pending.displayTitle)” is identical to “\(pending.existingTitle)”, "
              + "already in your library. Add another copy?"
          )
        }
    }
  }

  @ViewBuilder
  private var content: some View {
    if isSearching {
      ProgressView("Searching…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let message = errorMessage {
      ContentUnavailableView(
        "Couldn't search IFDB",
        systemImage: "exclamationmark.triangle",
        description: Text(message)
      )
    } else if searchText.isEmpty && results.isEmpty {
      IFDBCuratedListView { selected = $0 }
    } else {
      List(results) { result in
        resultRow(result)
      }
    }
  }

  private func resultRow(_ result: IFDBSearchResult) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Button { selected = result } label: {
        rowInfo(result)
      }
      .buttonStyle(.plain)
      .accessibilityHint("Shows description and details")

      Spacer()

      if downloading.contains(result.tuid) {
        ProgressView()
          .accessibilityLabel("Downloading \(result.title)")
      } else if downloaded.contains(result.tuid) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityLabel("\(result.title) downloaded")
      } else {
        Button("Download") { downloadGame(result) }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityLabel("Download \(result.title)")
          .accessibilityInputLabels(["Download"])
      }
    }
    .padding(.vertical, 4)
  }

  private func rowInfo(_ result: IFDBSearchResult) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(result.title).font(.headline)
      if let author = result.author {
        Text(author)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      metadata(result)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  /// Devsys chip, year, and rating. The Download button reserves a column for
  /// the whole row height, leaving this line narrow; rather than let the rating
  /// wrap mid-token ("4.5" / "(425)"), drop the whole line to two rows when it
  /// can't fit one. Each item is atomic via `fixedSize`, so nothing breaks
  /// inside a token, and the two-line fallback also covers larger Dynamic Type.
  private func metadata(_ result: IFDBSearchResult) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { metadataItems(result) }
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          if let devsys = result.devsys { devsysChip(devsys) }
          if let year = result.year { yearText(year) }
        }
        if let rating = result.ratingText {
          ratingLabel(rating, count: result.numRatings)
        }
      }
    }
  }

  @ViewBuilder
  private func metadataItems(_ result: IFDBSearchResult) -> some View {
    if let devsys = result.devsys { devsysChip(devsys) }
    if let year = result.year { yearText(year) }
    if let rating = result.ratingText {
      ratingLabel(rating, count: result.numRatings)
    }
  }

  private func devsysChip(_ devsys: String) -> some View {
    Text(devsys)
      .font(.caption)
      .padding(.horizontal, chipHorizontalPadding)
      .padding(.vertical, 3)
      .background(Capsule().fill(.blue.opacity(0.2)))
      .fixedSize(horizontal: true, vertical: false)
  }

  private func yearText(_ year: String) -> some View {
    Text(year)
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: true, vertical: false)
  }

  private func ratingLabel(_ rating: String, count: Int?) -> some View {
    let countSuffix = count.map { " (\($0))" } ?? ""
    // A manual HStack (not `Label`) so the star sits tight against the number
    // and the count never adaptively collapses to icon-only under width pressure.
    return HStack(spacing: 3) {
      Image(systemName: "star.fill")
      Text(rating + countSuffix)
    }
    .font(.caption)
    .foregroundStyle(.orange)
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      count.map { "\(rating) stars, \($0) ratings" } ?? "\(rating) star rating"
    )
  }

  private func performSearch() {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    errorMessage = nil
    isSearching = true
    Task {
      do {
        results = try await client.search(query: trimmed)
      } catch {
        errorMessage = "Search failed. \(error.localizedDescription)"
        results = []
      }
      isSearching = false
    }
  }

  private func downloadGame(_ result: IFDBSearchResult) {
    downloading.insert(result.tuid)
    Task {
      defer { downloading.remove(result.tuid) }
      do {
        let download = try await client.resolveDownload(tuid: result.tuid)
        let tempURL = try await client.downloadGame(download, title: result.title)
        // The network request succeeded — show the checkmark now, before the
        // dedup prompt (per design, fetch success is what the checkmark reports).
        downloaded.insert(result.tuid)
        ingest(tempURL: tempURL, displayTitle: result.title)
      } catch {
        downloadError = "\(result.title): \(error.localizedDescription)"
        showingDownloadError = true
      }
    }
  }

  /// Add the freshly downloaded temp file to the library, prompting first if it's
  /// byte-identical to a game already present.
  private func ingest(tempURL: URL, displayTitle: String) {
    if let existing = fileManager.contentDuplicate(of: tempURL) {
      pendingAdd = PendingStoryAdd(
        sourceURL: tempURL,
        preferredName: nil,
        existingTitle: existing.title,
        displayTitle: displayTitle
      )
    } else {
      save(tempURL: tempURL, preferredName: nil)
    }
  }

  private func commitPendingAdd(_ pending: PendingStoryAdd) {
    save(tempURL: pending.sourceURL, preferredName: pending.preferredName)
    pendingAdd = nil
  }

  private func cancelPendingAdd() {
    if let pending = pendingAdd { removeTempDirectory(of: pending.sourceURL) }
    pendingAdd = nil
  }

  private func save(tempURL: URL, preferredName: String?) {
    do {
      _ = try fileManager.addStory(from: tempURL, preferredName: preferredName)
    } catch {
      downloadError = error.localizedDescription
      showingDownloadError = true
    }
    removeTempDirectory(of: tempURL)
  }

  /// The client stages each download in its own temp directory; remove the whole
  /// directory once the file is copied into the library (or the add is canceled).
  private func removeTempDirectory(of fileURL: URL) {
    try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
  }
}
