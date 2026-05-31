import SwiftUI

struct IFDBBrowserView: View {
  var fileManager: StoryFileManager
  @Environment(\.dismiss) private var dismiss

  @State private var searchText = ""
  @State private var results: [IFDBSearchResult] = []
  @State private var isSearching = false
  @State private var downloading: Set<String> = []
  @State private var errorMessage: String?
  @State private var downloadError: String?
  @State private var showingDownloadError = false
  @State private var selected: IFDBSearchResult?
  private let client = IFDBClient()

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
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
          }
        }
        .overlay {
          if results.isEmpty && !isSearching && searchText.isEmpty {
            ContentUnavailableView(
              "Search IFDB",
              systemImage: "magnifyingglass",
              description: Text("Search for interactive fiction by title or author.")
            )
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
      HStack(spacing: 8) {
        if let devsys = result.devsys {
          Text(devsys)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.blue.opacity(0.2)))
        }
        if let year = result.year {
          Text(year)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let rating = result.ratingText {
          ratingLabel(rating, count: result.numRatings)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private func ratingLabel(_ rating: String, count: Int?) -> some View {
    let countSuffix = count.map { " (\($0))" } ?? ""
    return Label(rating + countSuffix, systemImage: "star.fill")
      .font(.caption)
      .foregroundStyle(.orange)
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
        let documents = FileManager.default.urls(
          for: .documentDirectory, in: .userDomainMask
        )[0]
        _ = try await client.downloadGame(download, title: result.title, to: documents)
        fileManager.refresh()
      } catch {
        downloadError = "\(result.title): \(error.localizedDescription)"
        showingDownloadError = true
      }
    }
  }
}
