import Testing
import Foundation
@testable import Diction

// Real IFDB /search?json=yes payloads return `starRating` as a JSON number
// (sometimes integral, sometimes a half-step like 2.5) and carry no `format`
// field — only `devsys`. The model must decode that shape.
@Test("Decodes IFDB search results with numeric star ratings and devsys")
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

// iFiction <downloads><links> lists cover art, zipped distributions, online-play
// links, and the story file all together. The resolver must pick the runnable,
// uncompressed story file — not the cover-art <url> that appears earlier.
private let zorkIFiction = """
<ifindex version="1.0" xmlns="http://babel.ifarchive.org/protocol/iFiction/">
<story>
<identification><ifid>ZCODE-88-840726</ifid><format>zcode</format></identification>
<bibliographic><title>Zork I</title></bibliographic>
<ifdb xmlns="http://ifdb.org/api/xmlns">
<link>https://ifdb.org/viewgame?id=0dbnusxunq7fw5ro</link>
<coverart><url>https://ifdb.org/coverart?id=0dbnusxunq7fw5ro&amp;version=45</url></coverart>
<primaryPlayOnlineUrl>https://iplayif.com/?story=zork1.z5</primaryPlayOnlineUrl>
<downloads><links>
<link>
<url>https://eblong.com/infocom/gamefiles/zork1.z5</url>
<playOnlineUrl>https://iplayif.com/?story=zork1.z5</playOnlineUrl>
<title>Zork 1</title><isGame/><format>zcode</format>
</link>
<link>
<url>http://www.infocom-if.org/downloads/zork1.zip</url>
<title>Zork I (Windows)</title><format>setup</format><compression>zip</compression>
</link>
<link>
<url>http://www.ifarchive.org/if-archive/games/vms/zorkvms.zip</url>
<isGame/><format>storyfile</format><compression>zip</compression>
</link>
</links></downloads>
</ifdb>
</story>
</ifindex>
"""

@Test("Resolves the playable Z-machine file, skipping cover art and zips")
func resolvesZMachineStoryFile() throws {
  let download = try #require(
    IFDBClient.playableDownload(fromIFiction: Data(zorkIFiction.utf8))
  )
  #expect(download.url.absoluteString == "https://eblong.com/infocom/gamefiles/zork1.z5")
  #expect(download.format == .zMachine)
}

@Test("Resolves a Glulx story file")
func resolvesGlulxStoryFile() throws {
  let xml = """
  <ifindex version="1.0" xmlns="http://babel.ifarchive.org/protocol/iFiction/">
  <story>
  <ifdb xmlns="http://ifdb.org/api/xmlns">
  <coverart><url>https://ifdb.org/coverart?id=x</url></coverart>
  <downloads><links>
  <link><url>https://example.org/cm.gblorb</url><isGame/><format>glulx</format></link>
  </links></downloads>
  </ifdb></story></ifindex>
  """
  let download = try #require(IFDBClient.playableDownload(fromIFiction: Data(xml.utf8)))
  #expect(download.url.absoluteString == "https://example.org/cm.gblorb")
  #expect(download.format == .glulx)
}

@Test("Returns nil when no runnable, uncompressed file exists")
func noPlayableFile() {
  // A TADS game with only a zipped non-VM download.
  let xml = """
  <ifindex version="1.0" xmlns="http://babel.ifarchive.org/protocol/iFiction/">
  <story>
  <ifdb xmlns="http://ifdb.org/api/xmlns">
  <coverart><url>https://ifdb.org/coverart?id=x</url></coverart>
  <downloads><links>
  <link><url>https://example.org/game.gam</url><isGame/><format>tads2</format></link>
  <link><url>https://example.org/zork.z5</url><isGame/><format>zcode</format><compression>zip</compression></link>
  </links></downloads>
  </ifdb></story></ifindex>
  """
  #expect(IFDBClient.playableDownload(fromIFiction: Data(xml.utf8)) == nil)
}
