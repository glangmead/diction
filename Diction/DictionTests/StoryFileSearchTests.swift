import Testing
import Foundation
@testable import Diction

@Suite("Story file search")
struct StoryFileSearchTests {
  private let lostPig = StoryFile(
    url: URL(fileURLWithPath: "/tmp/lostpig.ulx"),
    title: "lostpig",
    format: .glulx,
    source: .imported,
    lastPlayed: nil,
    metadata: StoryMetadata(
      title: "Lost Pig", author: "Admiral Jota", year: "2007",
      headline: "Comedy", versionLabel: "Glulx 3.1.1"
    )
  )

  private let devours = StoryFile(
    url: URL(fileURLWithPath: "/tmp/devours.z5"),
    title: "devours",
    format: .zMachine,
    source: .bundled,
    lastPlayed: nil,
    metadata: StoryMetadata(
      title: "All Things Devours", author: "half sick of shadows", year: "2004",
      headline: "Time Travel", versionLabel: "Release 3 · Serial 050325"
    )
  )

  @Test("matches the official title, case-insensitively")
  func title() {
    #expect(lostPig.matches("LOST"))
    #expect(lostPig.matches("pig"))
  }

  @Test("matches author, year, and headline")
  func catalogFields() {
    #expect(lostPig.matches("jota"))
    #expect(lostPig.matches("2007"))
    #expect(lostPig.matches("comedy"))
  }

  @Test("matches the version label")
  func version() {
    #expect(devours.matches("050325"))
    #expect(lostPig.matches("3.1.1"))
  }

  @Test("matches the format and source chips")
  func chips() {
    #expect(devours.matches("z-machine"))
    #expect(lostPig.matches("glulx"))
    #expect(devours.matches("bundled"))
    #expect(lostPig.matches("imported"))
  }

  @Test("token-AND: every word must appear, across fields")
  func tokenAnd() {
    #expect(lostPig.matches("jota lost"))       // author + title
    #expect(devours.matches("z-machine 2004"))  // format + year
    #expect(!lostPig.matches("jota zork"))      // "zork" absent
  }

  @Test("an empty query matches; an absent token does not")
  func edges() {
    #expect(lostPig.matches(""))
    #expect(lostPig.matches("   "))
    #expect(!lostPig.matches("anchorhead"))
  }
}
