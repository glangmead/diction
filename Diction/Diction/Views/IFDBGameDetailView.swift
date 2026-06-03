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
  @State private var downloadError: String?
  @State private var showingDownloadError = false

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
    isDownloading = true
    Task {
      defer { isDownloading = false }
      do {
        let documents = FileManager.default.urls(
          for: .documentDirectory, in: .userDomainMask
        )[0]
        _ = try await client.downloadGame(
          download,
          title: detail.title ?? fallbackTitle,
          to: documents
        )
        fileManager.refresh()
      } catch {
        downloadError = error.localizedDescription
        showingDownloadError = true
      }
    }
  }
}
