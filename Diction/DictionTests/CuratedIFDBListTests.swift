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

@Test("sortedGames orders each group by article-stripped title, ascending")
func sortedGamesIgnoresArticles() {
  for group in CuratedIFDBList.all.sections.flatMap(\.groups) {
    let keys = group.sortedGames.map { IFDBTitleSort.sortKey($0.title) }
    let ascending = keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    #expect(keys == ascending)
  }

  // "A Mind Forever Voyaging" now files under M, so "Adventure" leads the 50 Years group.
  let fiftyYears = CuratedIFDBList.all.sections.last?.groups.first
  #expect(fiftyYears?.sortedGames.first?.title == "Adventure")
}

@Test("Sort key drops a leading the/a/an, whole-word only; foreign articles kept")
func titleSortKey() {
  #expect(IFDBTitleSort.sortKey("The Lurking Horror") == "Lurking Horror")
  #expect(IFDBTitleSort.sortKey("A Mind Forever Voyaging") == "Mind Forever Voyaging")
  #expect(IFDBTitleSort.sortKey("An Adventure") == "Adventure")
  #expect(IFDBTitleSort.sortKey("Leather Goddesses of Phobos") == "Leather Goddesses of Phobos")
  #expect(IFDBTitleSort.sortKey("Lieux Communs") == "Lieux Communs")
  #expect(IFDBTitleSort.sortKey("Trinity") == "Trinity")
  #expect(IFDBTitleSort.sortKey("The") == "The")
  #expect(IFDBTitleSort.sortKey("El Museo de las Consciencias") == "El Museo de las Consciencias")
}

@Test("A group sorts its articles out of the way, stably")
func sortedGamesConcreteOrder() {
  let group = CuratedIFDBGroup(heading: nil, games: [
    CuratedIFDBGame("The Witness", tuid: "a"),
    CuratedIFDBGame("Ballyhoo", tuid: "b"),
    CuratedIFDBGame("A Mind Forever Voyaging", tuid: "c"),
    CuratedIFDBGame("Wishbringer", tuid: "d")
  ])
  #expect(group.sortedGames.map(\.title)
    == ["Ballyhoo", "A Mind Forever Voyaging", "Wishbringer", "The Witness"])
}

@Test("Language annotations are attached to the French and Spanish entries")
func annotations() {
  let games = CuratedIFDBList.all.sections.last?.groups.flatMap(\.games) ?? []
  #expect(games.first { $0.title == "Lieux Communs" }?.annotation == "(French)")
  #expect(games.first { $0.title == "El Museo de las Consciencias" }?.annotation == "(Spanish)")
  #expect(games.first { $0.title == "Adventure" }?.annotation == nil)
}
