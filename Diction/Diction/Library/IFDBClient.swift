import Foundation

/// One IFDB game record as returned by the search endpoint
/// (`/search?searchfor=…&json=yes`).
///
/// The search payload carries no runtime format — only `devsys`, the
/// authoring system (e.g. "ZIL", "Inform 7", "TADS 2"). The actual
/// Z-machine/Glulx format is resolved later from the iFiction XML.
nonisolated struct IFDBSearchResult: Identifiable, Sendable, Codable {
  var tuid: String
  var title: String
  var author: String?
  /// Authoring system, shown as a chip. IFDB calls this `devsys`.
  var devsys: String?
  /// IFDB returns this as a JSON number (whole or half-step, e.g. 4 or 2.5).
  var starRating: Double?

  var id: String { tuid }

  /// Rating formatted for display: "4", "2.5", or nil when unrated.
  var ratingText: String? {
    guard let starRating, starRating > 0 else { return nil }
    if starRating == starRating.rounded() {
      return String(Int(starRating))
    }
    return String(starRating)
  }
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

  /// Resolves a directly-downloadable Z-machine/Glulx story file for a
  /// given IFDB TUID by parsing the game's iFiction XML record. Throws
  /// `IFDBError.noDownloadURL` when the game offers no runnable, uncompressed
  /// story file (e.g. TADS/Hugo games, or download-only-as-zip listings).
  func resolveDownload(tuid: String) async throws -> IFDBDownload {
    var components = URLComponents(
      url: baseURL.appendingPathComponent("viewgame"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
      URLQueryItem(name: "ifiction", value: ""),
      URLQueryItem(name: "id", value: tuid)
    ]
    guard let url = components?.url else { throw IFDBError.invalidQuery }

    let (data, response) = try await session.data(from: url)
    try Self.ensureSuccess(response)

    guard let download = Self.playableDownload(fromIFiction: data) else {
      throw IFDBError.noDownloadURL
    }
    return download
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

  /// Picks the best playable story file out of an iFiction XML document.
  ///
  /// iFiction's `<downloads><links>` lists every associated file — cover art,
  /// solutions, zipped distributions, online-play links — so we cannot just
  /// take the first `<url>`. We select the first `<link>` whose `<format>` is
  /// a VM we run (zcode/glulx) and that carries no `<compression>` (the app's
  /// `FormatDetector` reads raw header bytes, not archives), preferring links
  /// explicitly marked `<isGame/>`.
  nonisolated static func playableDownload(fromIFiction data: Data) -> IFDBDownload? {
    let parser = XMLParser(data: data)
    let delegate = IFictionDownloadParser()
    parser.delegate = delegate
    parser.parse()
    return delegate.gameCandidate ?? delegate.anyCandidate
  }
}

/// Maps an iFiction `<format>` string to a runtime VM we support.
private func ifictionStoryFormat(_ raw: String) -> StoryFormat? {
  switch raw.lowercased() {
  case "zcode", "z-code":
    return .zMachine
  case "glulx":
    return .glulx
  default:
    return nil
  }
}

/// Streams an iFiction document, collecting download `<link>` entries from the
/// `<downloads>` section only — never the page link or cover-art `<url>` that
/// live elsewhere in the record.
private final class IFictionDownloadParser: NSObject, XMLParserDelegate {
  private(set) var gameCandidate: IFDBDownload?
  private(set) var anyCandidate: IFDBDownload?

  private var inDownloads = false
  private var inLink = false
  private var text = ""

  private var linkURL = ""
  private var linkFormat = ""
  private var linkIsGame = false
  private var linkCompressed = false

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName: String?,
    attributes: [String: String]
  ) {
    text = ""
    switch elementName {
    case "downloads":
      inDownloads = true
    case "link" where inDownloads:
      inLink = true
      linkURL = ""
      linkFormat = ""
      linkIsGame = false
      linkCompressed = false
    case "isGame" where inLink:
      linkIsGame = true
    case "compression" where inLink:
      linkCompressed = true
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName: String?
  ) {
    switch elementName {
    case "downloads":
      inDownloads = false
    case "url" where inLink:
      linkURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
    case "format" where inLink:
      linkFormat = text.trimmingCharacters(in: .whitespacesAndNewlines)
    case "link" where inLink:
      inLink = false
      evaluateLink()
    default:
      break
    }
    text = ""
  }

  private func evaluateLink() {
    guard !linkCompressed,
          let format = ifictionStoryFormat(linkFormat),
          let url = URL(string: linkURL) else { return }
    let candidate = IFDBDownload(url: url, format: format)
    if linkIsGame {
      if gameCandidate == nil { gameCandidate = candidate }
    } else if anyCandidate == nil {
      anyCandidate = candidate
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
