import Testing
import Foundation
@testable import Diction

// MARK: - Search decode

// Real IFDB /search?json=yes payloads return `starRating` as a JSON number
// (sometimes integral, sometimes a half-step like 2.5), carry `numRatings` and
// a nested `published` block, and have no `format` field — only `devsys`.
@Test("Decodes IFDB search results with numeric ratings, year, and counts")
func decodesSearchResults() throws {
  let json = Data("""
  [
    {"tuid":"0dbnusxunq7fw5ro","title":"Zork I","link":"https://ifdb.org/viewgame?id=zork1",
     "author":"Marc Blank and Dave Lebling","hasCoverArt":true,"devsys":"ZIL",
     "published":{"machine":"1980","printable":"1980"},
     "averageRating":3.81858407,"numRatings":226,"starRating":4,"starSort":3.69},
    {"tuid":"1ya4d9l464gpy7sh","title":"Zork: A Troll's-Eye View","link":"https://ifdb.org/viewgame?id=troll",
     "author":"Dylan O'Donnell","hasCoverArt":false,"devsys":"Inform 6",
     "published":{"machine":"1998","printable":"1998"},
     "averageRating":2.346153846,"numRatings":26,"starRating":2.5,"starSort":2.21}
  ]
  """.utf8)

  let results = try JSONDecoder().decode([IFDBSearchResult].self, from: json)

  #expect(results.count == 2)
  #expect(results.first?.title == "Zork I")
  #expect(results.first?.devsys == "ZIL")
  #expect(results.first?.starRating == 4)
  #expect(results.first?.year == "1980")
  #expect(results.first?.numRatings == 226)
  #expect(results.last?.author == "Dylan O'Donnell")
  #expect(results.last?.starRating == 2.5)
}

@Test("ratingText renders whole and half star values, nil when unrated")
func ratingText() {
  func result(_ rating: Double?) -> IFDBSearchResult {
    IFDBSearchResult(tuid: "t", title: "Title", author: nil, devsys: nil, starRating: rating)
  }
  #expect(result(4).ratingText == "4")
  #expect(result(2.5).ratingText == "2.5")
  #expect(result(3).ratingText == "3")
  #expect(result(nil).ratingText == nil)
  #expect(result(0).ratingText == nil)
}

// MARK: - Game detail decode + download selection

// A faithful subset of viewgame?id=…&json=yes for Shade. Its only playable
// links live on plain http at the IF Archive; the resolver must select the
// runnable, uncompressed one and upgrade it to https (the IF Archive serves
// the same file over TLS, so this dodges App Transport Security).
private let shadeDetailJSON = """
{
  "identification": {"format": "zcode"},
  "bibliographic": {
    "title": "Shade", "author": "Andrew Plotkin", "language": "English",
    "firstpublished": "2000", "genre": "Surreal",
    "description": "&quot;A one-room game set in your apartment.&quot; [--blurb]"
  },
  "ifdb": {
    "coverart": {"url": "https://ifdb.org/coverart?id=hsfc7fnl40k4a30q&version=20"},
    "playTimeInMinutes": 60,
    "averageRating": 3.875862068, "starRating": 4, "ratingCountTot": 435,
    "downloads": {"links": [
      {"url": "http://www.ifarchive.org/if-archive/games/zcode/shade.z5",
       "title": "shade.z5", "isGame": true, "format": "zcode"},
      {"url": "http://www.ifarchive.org/if-archive/games/mac/Shade-R3.hqx",
       "isGame": true, "format": "executable", "compression": "bin/hex"},
      {"url": "https://www.allthingsjacq.com/transcript.html",
       "isGame": false, "format": "html"}
    ]},
    "tags": [
      {"name": "apartment", "tagcnt": 1, "gamecnt": 22},
      {"name": "one-room", "tagcnt": 5, "gamecnt": 80}
    ]
  }
}
"""

@Test("Decodes a game detail record's display fields")
func decodesGameDetail() throws {
  let detail = try JSONDecoder().decode(IFDBGameDetail.self, from: Data(shadeDetailJSON.utf8))

  #expect(detail.title == "Shade")
  #expect(detail.author == "Andrew Plotkin")
  #expect(detail.genre == "Surreal")
  #expect(detail.firstPublished == "2000")
  #expect(detail.formatLabel == "Z-machine")
  #expect(detail.ratingText == "4")
  #expect(detail.ifdb?.ratingCountTot == 435)
  #expect(detail.playtimeText == "1 hr")
  #expect(detail.tags.count == 2)
  #expect(detail.tags.first?.name == "apartment")
  #expect(detail.coverArtURL?.absoluteString.contains("coverart?id=hsfc7fnl40k4a30q") == true)
  // HTML entities are decoded for display (Markdown for the attributed render).
  #expect(detail.descriptionMarkdown?.hasPrefix("\"A one-room game") == true)
}

@Test("Selects the runnable Z-machine file and upgrades http to https")
func resolvesZMachineWithHTTPSUpgrade() throws {
  let detail = try JSONDecoder().decode(IFDBGameDetail.self, from: Data(shadeDetailJSON.utf8))
  let download = try #require(detail.playableDownload)
  #expect(download.url.absoluteString == "https://www.ifarchive.org/if-archive/games/zcode/shade.z5")
  #expect(download.format == .zMachine)
}

@Test("Selects a Glulx file, leaving an https URL untouched")
func resolvesGlulx() throws {
  let json = """
  {"ifdb": {"downloads": {"links": [
    {"url": "https://example.org/cm.gblorb", "isGame": true, "format": "glulx"}
  ]}}}
  """
  let detail = try JSONDecoder().decode(IFDBGameDetail.self, from: Data(json.utf8))
  let download = try #require(detail.playableDownload)
  #expect(download.url.absoluteString == "https://example.org/cm.gblorb")
  #expect(download.format == .glulx)
}

@Test("Returns nil when no runnable, uncompressed file exists")
func noPlayableFile() throws {
  let json = """
  {"ifdb": {"downloads": {"links": [
    {"url": "https://example.org/game.gam", "isGame": true, "format": "tads2"},
    {"url": "http://example.org/zork.z5", "isGame": true, "format": "zcode", "compression": "zip"}
  ]}}}
  """
  let detail = try JSONDecoder().decode(IFDBGameDetail.self, from: Data(json.utf8))
  #expect(detail.playableDownload == nil)
}

@Test("Resolves a Blorb-wrapped Glulx game (IFDB 'blorb/glulx'), skipping the zip")
func resolvesBlorbGlulx() throws {
  // Blue Lacuna's exact link shape: a .gblorb tagged "blorb/glulx" plus a zip.
  let json = """
  {"ifdb": {"downloads": {"links": [
    {"url": "https://ifarchive.org/glulx/BlueLacuna.gblorb", "isGame": true, "format": "blorb/glulx"},
    {"url": "https://ifarchive.org/st08/BlueLacuna.zip", "isGame": true, "format": "blorb/glulx", "compression": "zip"}
  ]}}}
  """
  let detail = try JSONDecoder().decode(IFDBGameDetail.self, from: Data(json.utf8))
  let download = try #require(detail.playableDownload)
  #expect(download.url.absoluteString == "https://ifarchive.org/glulx/BlueLacuna.gblorb")
  #expect(download.format == .glulx)
}
