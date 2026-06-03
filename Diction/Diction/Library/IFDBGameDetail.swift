import Foundation

/// A game's full IFDB record, decoded from `viewgame?id=<tuid>&json=yes`.
/// This is the same data IFDB also exports as iFiction XML, but JSON lets us
/// decode it with `Codable` instead of hand-rolling an XML parser. It backs the
/// detail view and supplies the download links the resolver chooses from.
nonisolated struct IFDBGameDetail: Sendable, Codable {
  var identification: Identification?
  var bibliographic: Bibliographic?
  var ifdb: IFDBSection?

  nonisolated struct Identification: Sendable, Codable {
    /// Runtime VM, e.g. "zcode", "glulx", "tads3".
    var format: String?
  }

  nonisolated struct Bibliographic: Sendable, Codable {
    var title: String?
    var author: String?
    var language: String?
    var firstpublished: String?
    var genre: String?
    /// Prose blurb, HTML-entity-encoded by IFDB (see `descriptionText`).
    var description: String?
  }

  nonisolated struct IFDBSection: Sendable, Codable {
    var coverart: CoverArt?
    var playTimeInMinutes: Int?
    var averageRating: Double?
    var starRating: Double?
    var ratingCountTot: Int?
    var downloads: Downloads?
    var tags: [Tag]?
  }

  nonisolated struct CoverArt: Sendable, Codable {
    var url: String?
  }

  nonisolated struct Downloads: Sendable, Codable {
    var links: [DownloadLink]?
  }

  nonisolated struct DownloadLink: Sendable, Codable {
    var url: String?
    var isGame: Bool?
    var format: String?
    var compression: String?
  }

  nonisolated struct Tag: Sendable, Codable, Identifiable {
    var name: String
    var gamecnt: Int?
    var id: String { name }
  }

  // MARK: - Display

  var title: String? { bibliographic?.title }
  var author: String? { bibliographic?.author }
  var genre: String? { bibliographic?.genre }
  var firstPublished: String? { bibliographic?.firstpublished }
  var language: String? { bibliographic?.language }
  var tags: [Tag] { ifdb?.tags ?? [] }
  var ratingText: String? { starRatingText(ifdb?.starRating) }

  var coverArtURL: URL? {
    ifdb?.coverart?.url.flatMap { URL(string: $0) }
  }

  /// The blurb as plain text — IFDB stores it as HTML (tags + entities).
  var descriptionText: String? {
    bibliographic?.description.map(plainText(fromIFDBHTML:))
  }

  /// Human label for the runtime format ("Z-machine", "Glulx", or the raw
  /// string for anything we don't run).
  var formatLabel: String? {
    guard let format = identification?.format else { return nil }
    switch ifictionStoryFormat(format) {
    case .zMachine: return "Z-machine"
    case .glulx: return "Glulx"
    case .none: return format
    }
  }

  /// Rounded playtime estimate, e.g. "45 min" or "9 hr".
  var playtimeText: String? {
    guard let minutes = ifdb?.playTimeInMinutes, minutes > 0 else { return nil }
    if minutes < 60 { return "\(minutes) min" }
    return "\(Int((Double(minutes) / 60).rounded())) hr"
  }

  /// The best directly-downloadable Z-machine/Glulx story file.
  ///
  /// `downloads.links` lists everything associated with the game — cover art,
  /// solutions, zipped distributions, online-play links — so we select the
  /// first link whose `format` is a VM we run (zcode/glulx) and that carries no
  /// `compression` (the app's `FormatDetector` reads raw header bytes, not
  /// archives), preferring links marked `isGame`. The chosen URL is upgraded to
  /// https so App Transport Security doesn't block plain-http IF Archive files.
  var playableDownload: IFDBDownload? {
    let links = ifdb?.downloads?.links ?? []
    let runnable = links.compactMap { link -> (isGame: Bool, download: IFDBDownload)? in
      guard link.compression == nil,
            let raw = link.url,
            let url = URL(string: raw),
            let format = ifictionStoryFormat(link.format ?? "") else { return nil }
      return (link.isGame == true, IFDBDownload(url: httpsUpgraded(url), format: format))
    }
    return (runnable.first { $0.isGame } ?? runnable.first)?.download
  }
}

/// Upgrades an `http` URL to `https`, leaving other schemes untouched. The
/// IF Archive and the other common IF mirrors all serve their files over TLS.
private func httpsUpgraded(_ url: URL) -> URL {
  guard url.scheme?.lowercased() == "http",
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
    return url
  }
  components.scheme = "https"
  return components.url ?? url
}

/// Maps an iFiction/IFDB `format` string to a runtime VM we support. IFDB tags
/// Blorb-wrapped games as `blorb/glulx` or `blorb/zcode` (and bare `glulx` /
/// `zcode` / `z-code`), so match the VM name within the string rather than
/// exact-matching. The downloaded file's real format is re-confirmed from its
/// bytes by `FormatDetector` (a `.gblorb` resolves to `.glulx` via its inner
/// `GLUL` chunk), so picking `.glulx` here for `blorb/glulx` is correct.
func ifictionStoryFormat(_ raw: String) -> StoryFormat? {
  let format = raw.lowercased()
  if format.contains("glulx") { return .glulx }
  if format.contains("zcode") || format.contains("z-code") { return .zMachine }
  return nil
}

/// Formats a half-step star rating for display: "4", "2.5", or nil when unrated.
func starRatingText(_ rating: Double?) -> String? {
  guard let rating, rating > 0 else { return nil }
  if rating == rating.rounded() {
    return String(Int(rating))
  }
  return String(rating)
}

/// Renders the HTML that IFDB stores in prose fields into clean plain text for a
/// SwiftUI `Text`. IFDB blurbs carry real markup — `<br>`, `<p>`, `<i>`, `<a>`,
/// `<ul><li>` — and entity-encoded characters like `&#039;`, none of which a raw
/// `Text` would render. Structural tags become line breaks (list items become
/// bullets), inline tags are dropped, then entities are decoded and whitespace
/// tidied.
func plainText(fromIFDBHTML html: String) -> String {
  guard html.contains("<") || html.contains("&") else { return html }
  let regex: NSString.CompareOptions = [.regularExpression, .caseInsensitive]
  var text = html
  // `\n` here is a literal newline scalar, not a backslash escape, so it's safe
  // as a regex-replacement template (which only treats `$` and `\` specially).
  text = text.replacingOccurrences(of: "<\\s*br\\s*/?\\s*>", with: "\n", options: regex)
  text = text.replacingOccurrences(of: "<\\s*li\\b[^>]*>", with: "\n\u{2022} ", options: regex)
  // Block boundaries (not <li>; its closing tag is dropped by the strip below so
  // each item stays single-spaced).
  text = text.replacingOccurrences(
    of: "<\\s*/?\\s*(p|div|ul|ol|h[1-6]|blockquote|tr|table)\\b[^>]*>",
    with: "\n", options: regex
  )
  text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: [.regularExpression])
  text = decodeHTMLEntities(text)
  text = text.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: [.regularExpression])
  text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: [.regularExpression])
  return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Decodes HTML character entities — decimal (`&#039;`), hex (`&#xE9;`), and a
/// common named set (`&amp;`, `&mdash;`, …) — in a single left-to-right pass.
/// One pass means a double-encoded `&amp;#039;` resolves only its outer `&amp;`,
/// surviving as the literal text `&#039;` rather than collapsing to `'`. A `&`
/// that doesn't open a recognized entity (and any unknown `&name;`) is left
/// untouched, so "AT&T" stays "AT&T".
func decodeHTMLEntities(_ string: String) -> String {
  guard string.contains("&") else { return string }
  var result = ""
  result.reserveCapacity(string.count)
  var index = string.startIndex
  while index < string.endIndex {
    guard string[index] == "&",
          let semicolon = string[index...].firstIndex(of: ";"),
          string.distance(from: index, to: semicolon) <= 12 else {
      result.append(string[index])
      index = string.index(after: index)
      continue
    }
    let body = String(string[string.index(after: index)..<semicolon])
    if let decoded = decodeHTMLEntityBody(body) {
      result.append(decoded)
      index = string.index(after: semicolon)
    } else {
      result.append(string[index])
      index = string.index(after: index)
    }
  }
  return result
}

/// Decodes the inside of a single `&…;` entity (no ampersand or semicolon).
/// Returns nil for anything unrecognized so the caller can leave it literal.
private func decodeHTMLEntityBody(_ body: String) -> String? {
  if body.hasPrefix("#") {
    let digits = body.dropFirst()
    let value: UInt32? = (digits.first == "x" || digits.first == "X")
      ? UInt32(digits.dropFirst(), radix: 16)
      : UInt32(digits, radix: 10)
    guard let value, let scalar = Unicode.Scalar(value) else { return nil }
    return String(scalar)
  }
  return htmlNamedEntities[body]
}

/// Named entities common in IFDB prose. The decimal/hex path covers the long
/// tail, so this only needs the names IFDB actually emits unencoded.
private let htmlNamedEntities: [String: String] = [
  "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
  "mdash": "—", "ndash": "–", "hellip": "…", "bull": "•", "middot": "·",
  "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
  "copy": "©", "reg": "®", "trade": "™", "deg": "°", "times": "×",
  "eacute": "é", "egrave": "è", "ecirc": "ê", "agrave": "à", "acirc": "â",
  "uuml": "ü", "ouml": "ö", "auml": "ä", "iuml": "ï", "euml": "ë",
  "ntilde": "ñ", "ccedil": "ç", "szlig": "ß", "oslash": "ø", "aring": "å",
  "frac12": "½", "frac14": "¼", "pound": "£", "euro": "€", "cent": "¢"
]
