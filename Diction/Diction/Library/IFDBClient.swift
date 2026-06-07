import Foundation

/// One IFDB game record as returned by the search endpoint
/// (`/search?searchfor=…&json=yes`).
///
/// The search payload carries no runtime format — only `devsys`, the
/// authoring system (e.g. "ZIL", "Inform 7", "TADS 2"). The actual
/// Z-machine/Glulx format and download links come from the per-game
/// `IFDBGameDetail` record.
nonisolated struct IFDBSearchResult: Identifiable, Sendable, Codable, Hashable {
  var tuid: String
  var title: String
  var author: String?
  /// Authoring system, shown as a chip. IFDB calls this `devsys`.
  var devsys: String?
  /// IFDB returns this as a JSON number (whole or half-step, e.g. 4 or 2.5).
  var starRating: Double?
  /// Number of member ratings backing `starRating`.
  var numRatings: Int?
  var published: Published?

  init(
    tuid: String,
    title: String,
    author: String? = nil,
    devsys: String? = nil,
    starRating: Double? = nil,
    numRatings: Int? = nil,
    published: Published? = nil
  ) {
    self.tuid = tuid
    self.title = title
    self.author = author
    self.devsys = devsys
    self.starRating = starRating
    self.numRatings = numRatings
    self.published = published
  }

  var id: String { tuid }

  nonisolated struct Published: Sendable, Codable, Hashable {
    var machine: String?
    var printable: String?
  }

  /// First-published year for display, e.g. "1980".
  var year: String? { published?.printable ?? published?.machine }

  /// Rating formatted for display: "4", "2.5", or nil when unrated.
  var ratingText: String? { starRatingText(starRating) }
}

/// A resolved, directly-downloadable story file for a game.
nonisolated struct IFDBDownload: Sendable, Equatable {
  var url: URL
  var format: StoryFormat
}

/// Talks to the IFDB public API.
/// IFDB's API documentation is at https://ifdb.org/help-api.
actor IFDBClient {
  private let session: URLSession
  private let baseURL = URL(string: "https://ifdb.org")!

  init(session: URLSession = .shared) {
    self.session = session
  }

  func search(query: String) async throws -> [IFDBSearchResult] {
    var components = URLComponents(
      url: baseURL.appendingPathComponent("search"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
      URLQueryItem(name: "searchfor", value: query),
      URLQueryItem(name: "json", value: "yes")
    ]
    guard let url = components?.url else {
      throw IFDBError.invalidQuery
    }

    let (data, response) = try await session.data(from: url)
    try Self.ensureSuccess(response)

    // IFDB's JSON wraps results in {"games": [...]}.
    if let envelope = try? JSONDecoder().decode(SearchEnvelope.self, from: data) {
      return envelope.games ?? []
    }
    // Fall back to a bare array if the envelope shape changed.
    return (try? JSONDecoder().decode([IFDBSearchResult].self, from: data)) ?? []
  }

  /// Fetches a game's full IFDB record (`viewgame?id=…&json=yes`), which backs
  /// the detail view and supplies the download links.
  func gameDetail(tuid: String) async throws -> IFDBGameDetail {
    var components = URLComponents(
      url: baseURL.appendingPathComponent("viewgame"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
      URLQueryItem(name: "id", value: tuid),
      URLQueryItem(name: "json", value: "yes")
    ]
    guard let url = components?.url else { throw IFDBError.invalidQuery }

    let (data, response) = try await session.data(from: url)
    try Self.ensureSuccess(response)
    return try JSONDecoder().decode(IFDBGameDetail.self, from: data)
  }

  /// Best-effort cover-image fetch for persisting a downloaded game's art. Returns
  /// nil on any failure (no URL, network error, non-2xx) — the cover is optional.
  func downloadCoverImage(from url: URL?) async -> Data? {
    guard let url,
      let (data, response) = try? await session.data(from: url),
      let http = response as? HTTPURLResponse,
      (200..<300).contains(http.statusCode)
    else { return nil }
    return data
  }

  /// Downloads a resolved story file into a fresh temporary directory, naming it
  /// after the game title, and returns the saved file's URL. The caller hands this
  /// URL to `StoryFileManager` (which dedups and copies it into the library under a
  /// unique name) and is responsible for removing the temp directory afterward.
  func downloadGame(_ download: IFDBDownload, title: String) async throws -> URL {
    let ext = download.url.pathExtension.isEmpty ? "z5" : download.url.pathExtension
    let safeTitle = title
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ifdb-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let destination = tempDir.appendingPathComponent("\(safeTitle).\(ext)")
    try await self.download(from: download.url, to: destination)
    return destination
  }

  /// Downloads a story file from the resolved URL into the given destination.
  func download(from url: URL, to destination: URL) async throws {
    let (tempURL, response) = try await session.download(from: url)
    try Self.ensureSuccess(response)
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: tempURL, to: destination)
  }

  // MARK: - Internals

  private struct SearchEnvelope: Codable {
    var games: [IFDBSearchResult]?
  }

  private static func ensureSuccess(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else {
      throw IFDBError.requestFailed
    }
    guard (200..<300).contains(http.statusCode) else {
      throw IFDBError.requestFailed
    }
  }
}

enum IFDBError: LocalizedError {
  case invalidQuery
  case requestFailed
  case noDownloadURL

  var errorDescription: String? {
    switch self {
    case .invalidQuery:
      return "That search couldn't be performed."
    case .requestFailed:
      return "Couldn't reach IFDB."
    case .noDownloadURL:
      return "No Z-machine or Glulx story file is available for this game."
    }
  }
}
