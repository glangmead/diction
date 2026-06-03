import Testing
import Foundation
@testable import Diction

// The curated catalog is hand-maintained Swift data mirroring
// `nocommit/ifdb_links.md`. These tests guard its invariants so a bad edit
// (empty tuid, a playable graphical game, a dropped annotation) fails the build.

@Test("Curated list has two sections; only the book title in the 50 Years header links")
func curatedSections() throws {
  let list = CuratedIFDBList.all
  #expect(list.sections.count == 2)

  let lostTreasures = try #require(list.sections.first)
  #expect(String(lostTreasures.title.characters) == "Lost Treasures of Infocom I, II, CD-ROM")
  #expect(lostTreasures.title.runs.allSatisfy { $0.link == nil })

  let fiftyYears = try #require(list.sections.last)
  #expect(String(fiftyYears.title.characters) == "Mentioned in 50 Years of Text Games by Aaron A. Reed")
  let linkRun = try #require(fiftyYears.title.runs.first { $0.link != nil })
  #expect(linkRun.link?.host == "aaronareed.net")
  // Only the book title is the link — not "Mentioned in" or "by Aaron A. Reed".
  #expect(String(fiftyYears.title[linkRun.range].characters) == "50 Years of Text Games")
}

@Test("Every playable game carries a non-empty tuid")
func playableGamesHaveTUIDs() {
  for section in CuratedIFDBList.all.sections {
    for game in section.groups.flatMap(\.games) where game.isPlayable {
      #expect(!game.tuid.isEmpty, "\(game.title) has an empty tuid")
    }
  }
}

@Test("The Not supported yet group is exactly Arthur and Journey, non-playable")
func notSupportedGroup() {
  let lostTreasures = CuratedIFDBList.all.sections.first
  let group = lostTreasures?.groups.first { $0.heading == "Not supported yet" }
  #expect(group?.games.map(\.title) == ["Arthur: The Quest for Excalibur", "Journey"])
  #expect(group?.games.allSatisfy { !$0.isPlayable } == true)
}

@Test("Only the Not supported yet group is non-playable; all other games link out")
func playabilityByGroup() {
  for section in CuratedIFDBList.all.sections {
    for group in section.groups {
      let expected = group.heading != "Not supported yet"
      #expect(group.games.allSatisfy { $0.isPlayable == expected })
    }
  }
}

@Test("sortedGames orders each group's titles locale-ascending")
func sortedGamesIsAlphabetical() {
  for group in CuratedIFDBList.all.sections.flatMap(\.groups) {
    let titles = group.sortedGames.map(\.title)
    let expected = titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    #expect(titles == expected)
  }

  // Article-led titles collate on the literal title: "A Mind…" sorts first.
  let fiftyYears = CuratedIFDBList.all.sections.last?.groups.first
  #expect(fiftyYears?.sortedGames.first?.title == "A Mind Forever Voyaging")
}

@Test("Language annotations are attached to the French and Spanish entries")
func annotations() {
  let games = CuratedIFDBList.all.sections.last?.groups.flatMap(\.games) ?? []
  #expect(games.first { $0.title == "Lieux Communs" }?.annotation == "(French)")
  #expect(games.first { $0.title == "El Museo de las Consciencias" }?.annotation == "(Spanish)")
  #expect(games.first { $0.title == "Adventure" }?.annotation == nil)
}
