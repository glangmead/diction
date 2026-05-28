import Foundation

/// One IFDB game record as returned by the search endpoint.
nonisolated struct IFDBSearchResult: Identifiable, Sendable, Codable {
  var tuid: String
  var title: String
  var author: String?
  var starRating: String?
  var format: String?

  var id: String { tuid }

  var storyFormat: StoryFormat? {
    switch format?.lowercased() {
    case "zcode", "z-code", "z3", "z5", "z8":
      return .zMachine
    case "glulx":
      return .glulx
    default:
      return nil
    }
  }
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
      URLQueryItem(name: "json", value: "yes"),
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

  /// Resolves the download URL for a given IFDB TUID. Parses iFiction XML
  /// for the first `<url>` element it finds.
  func downloadURL(tuid: String) async throws -> URL? {
    var components = URLComponents(
      url: baseURL.appendingPathComponent("viewgame"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
      URLQueryItem(name: "ifiction", value: ""),
      URLQueryItem(name: "id", value: tuid),
    ]
    guard let url = components?.url else { return nil }

    let (data, response) = try await session.data(from: url)
    try Self.ensureSuccess(response)

    guard let xml = String(data: data, encoding: .utf8) else { return nil }
    if let urlString = extractFirstURL(in: xml) {
      return URL(string: urlString)
    }
    return nil
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

  private nonisolated func extractFirstURL(in xml: String) -> String? {
    guard let openRange = xml.range(of: "<url>") else { return nil }
    let tail = xml[openRange.upperBound...]
    guard let closeRange = tail.range(of: "</url>") else { return nil }
    return String(tail[..<closeRange.lowerBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum IFDBError: Error {
  case invalidQuery
  case requestFailed
  case noDownloadURL
}
