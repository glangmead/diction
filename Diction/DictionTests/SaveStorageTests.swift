import Testing
import Foundation
@testable import Diction

@Test("emglkenFileURL scopes a basename under the game's save dir and is stable")
func emglkenFileURLMapping() throws {
  let url = try #require(SaveStorage.emglkenFileURL(gameID: "curses", basename: "save.glksave"))
  #expect(url.path.contains("/Saves/curses/"))
  #expect(url.lastPathComponent == "save.glksave")
  #expect(SaveStorage.emglkenFileURL(gameID: "curses", basename: "save.glksave") == url)  // stable
  // Path traversal in a basename must not escape the game dir.
  let evil = SaveStorage.emglkenFileURL(gameID: "curses", basename: "../../etc/passwd")
  #expect(evil == nil)
}
