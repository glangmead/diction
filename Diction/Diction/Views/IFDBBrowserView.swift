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
  private let client = IFDBClient()

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Browse IFDB")
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
          isPresented: Binding(
            get: { downloadError != nil },
            set: { if !$0 { downloadError = nil } }
          ),
          presenting: downloadError
        ) { _ in
          Button("OK", role: .cancel) {}
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
          if let rating = result.ratingText {
            Label(rating, systemImage: "star.fill")
              .font(.caption)
              .foregroundStyle(.orange)
              .accessibilityLabel("\(rating) star rating")
          }
        }
      }
      .accessibilityElement(children: .combine)

      Spacer()

      if downloading.contains(result.tuid) {
        ProgressView()
          .accessibilityLabel("Downloading \(result.title)")
      } else {
        Button("Download") { downloadGame(result) }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityLabel("Download \(result.title)")
      }
    }
    .padding(.vertical, 4)
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
        let ext = download.url.pathExtension.isEmpty ? "z5" : download.url.pathExtension
        let safeTitle = result.title
          .replacingOccurrences(of: "/", with: "-")
          .replacingOccurrences(of: ":", with: "-")
        let filename = "\(safeTitle).\(ext)"
        let dest = FileManager.default.urls(
          for: .documentDirectory, in: .userDomainMask
        )[0].appendingPathComponent(filename)

        try await client.download(from: download.url, to: dest)
        fileManager.refresh()
      } catch {
        downloadError = "\(result.title): \(error.localizedDescription)"
      }
    }
  }
}
