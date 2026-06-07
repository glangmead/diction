import SwiftUI

/// Shows an IFDB game's full record — cover art, metadata, description, tags —
/// fetched lazily on appear, with a Download action. Reached by tapping a
/// search result in `IFDBBrowserView`.
struct IFDBGameDetailView: View {
  let tuid: String
  let fallbackTitle: String
  var fileManager: StoryFileManager

  private let client = IFDBClient()

  @State private var detail: IFDBGameDetail?
  @State private var isLoading = true
  @State private var loadError: String?
  @State private var isDownloading = false
  /// Set once the download network request succeeds; flips the button to a
  /// checkmark for the rest of this view's lifetime.
  @State private var didDownload = false
  @State private var downloadError: String?
  @State private var showingDownloadError = false
  @State private var pendingAdd: PendingStoryAdd?

  /// Horizontal inset for tag capsules. A `Capsule`'s corner radius is half its
  /// height, so the text needs at least that much side padding to clear the
  /// rounded ends; scaled with the caption font so it keeps clearing them as
  /// Dynamic Type grows the capsule.
  @ScaledMetric(relativeTo: .caption) private var tagHorizontalPadding: CGFloat = 12

  var body: some View {
    content
      .navigationTitle(detail?.title ?? fallbackTitle)
      .navigationBarTitleDisplayMode(.inline)
      .task { await load() }
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

  @ViewBuilder
  private var content: some View {
    if isLoading {
      ProgressView("Loading…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let loadError {
      ContentUnavailableView(
        "Couldn't load details",
        systemImage: "exclamationmark.triangle",
        description: Text(loadError)
      )
    } else if let detail {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          coverArt(detail)
          header(detail)
          downloadSection(detail)
          if let description = detail.descriptionMarkdown, !description.isEmpty {
            section("About") {
              Text(Self.attributedDescription(description))
                .font(.body)
            }
          }
          metadata(detail)
          tagsSection(detail)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private func coverArt(_ detail: IFDBGameDetail) -> some View {
    if let url = detail.coverArtURL {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFit()
        case .failure:
          EmptyView()
        default:
          ProgressView()
        }
      }
      .frame(maxWidth: .infinity)
      .frame(maxHeight: 240)
      .accessibilityLabel("Cover art for \(detail.title ?? fallbackTitle)")
    }
  }

  private func header(_ detail: IFDBGameDetail) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(detail.title ?? fallbackTitle)
        .font(.title2.bold())
      if let author = detail.author {
        Text(author)
          .font(.headline)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func downloadSection(_ detail: IFDBGameDetail) -> some View {
    if isDownloading {
      ProgressView("Downloading…")
    } else if didDownload {
      Label("Downloaded", systemImage: "checkmark.circle")
        .frame(maxWidth: .infinity)
        .foregroundStyle(.green)
    } else if detail.playableDownload != nil {
      Button {
        download(detail)
      } label: {
        Label("Download", systemImage: "arrow.down.circle")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
    } else {
      Label(
        "No Z-machine or Glulx download available.",
        systemImage: "nosign"
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func metadata(_ detail: IFDBGameDetail) -> some View {
    let rows = metadataRows(detail)
    if !rows.isEmpty {
      section("Details") {
        VStack(spacing: 8) {
          ForEach(rows, id: \.label) { row in
            LabeledContent(row.label, value: row.value)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func tagsSection(_ detail: IFDBGameDetail) -> some View {
    if !detail.tags.isEmpty {
      section("Tags") {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(detail.tags) { tag in
            Text(tag.name)
              .font(.caption)
              .padding(.horizontal, tagHorizontalPadding)
              .padding(.vertical, 4)
              .background(Capsule().fill(.secondary.opacity(0.15)))
          }
        }
      }
    }
  }

  private func section<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Parses the blurb's Markdown for display. `inlineOnlyPreservingWhitespace`
  /// keeps the converter's line breaks and bullets verbatim while still styling
  /// emphasis and making links tappable; a parse failure falls back to the raw
  /// text rather than dropping the description.
  private static func attributedDescription(_ markdown: String) -> AttributedString {
    var options = AttributedString.MarkdownParsingOptions()
    options.interpretedSyntax = .inlineOnlyPreservingWhitespace
    options.failurePolicy = .returnPartiallyParsedIfPossible
    return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
  }

  // MARK: - Data

  private func metadataRows(_ detail: IFDBGameDetail) -> [(label: String, value: String)] {
    var rows: [(label: String, value: String)] = []
    if let genre = detail.genre { rows.append(("Genre", genre)) }
    if let year = detail.firstPublished { rows.append(("First published", year)) }
    if let language = detail.language { rows.append(("Language", language)) }
    if let format = detail.formatLabel { rows.append(("Format", format)) }
    if let playtime = detail.playtimeText { rows.append(("Playtime", playtime)) }
    if let rating = detail.ratingText {
      let count = detail.ifdb?.ratingCountTot
      rows.append(("Rating", count.map { "\(rating) (\($0) ratings)" } ?? rating))
    }
    return rows
  }

  private func load() async {
    isLoading = true
    loadError = nil
    do {
      detail = try await client.gameDetail(tuid: tuid)
    } catch {
      loadError = error.localizedDescription
    }
    isLoading = false
  }

  private func download(_ detail: IFDBGameDetail) {
    guard let download = detail.playableDownload else {
      downloadError = IFDBError.noDownloadURL.localizedDescription
      showingDownloadError = true
      return
    }
    let title = detail.title ?? fallbackTitle
    isDownloading = true
    Task {
      defer { isDownloading = false }
      do {
        let cover = await client.downloadCoverImage(from: detail.coverArtURL)
        let tempURL = try await client.downloadGame(download, title: title)
        // Fetch succeeded — show the checkmark now, ahead of any dedup prompt.
        didDownload = true
        ingest(
          tempURL: tempURL, displayTitle: title,
          supplemental: detail.storyMetadata, coverImage: cover
        )
      } catch {
        downloadError = error.localizedDescription
        showingDownloadError = true
      }
    }
  }

}

// MARK: - Library ingest & dedup

extension IFDBGameDetailView {
  /// Add the freshly downloaded temp file to the library, prompting first if it's
  /// byte-identical to a game already present.
  fileprivate func ingest(
    tempURL: URL, displayTitle: String,
    supplemental: StoryMetadata? = nil, coverImage: Data? = nil
  ) {
    if let existing = fileManager.contentDuplicate(of: tempURL) {
      pendingAdd = PendingStoryAdd(
        sourceURL: tempURL,
        preferredName: nil,
        existingTitle: existing.title,
        displayTitle: displayTitle,
        supplemental: supplemental,
        coverImage: coverImage
      )
    } else {
      save(tempURL: tempURL, preferredName: nil, supplemental: supplemental, coverImage: coverImage)
    }
  }

  fileprivate func commitPendingAdd(_ pending: PendingStoryAdd) {
    save(
      tempURL: pending.sourceURL, preferredName: pending.preferredName,
      supplemental: pending.supplemental, coverImage: pending.coverImage
    )
    pendingAdd = nil
  }

  fileprivate func cancelPendingAdd() {
    if let pending = pendingAdd { removeTempDirectory(of: pending.sourceURL) }
    pendingAdd = nil
  }

  private func save(
    tempURL: URL, preferredName: String?,
    supplemental: StoryMetadata? = nil, coverImage: Data? = nil
  ) {
    do {
      _ = try fileManager.addStory(
        from: tempURL, preferredName: preferredName,
        supplemental: supplemental, coverImage: coverImage
      )
    } catch {
      downloadError = error.localizedDescription
      showingDownloadError = true
    }
    removeTempDirectory(of: tempURL)
  }

  private func removeTempDirectory(of fileURL: URL) {
    try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
  }
}
