import Testing
import Foundation
@testable import Diction

/// Each test gets its own temp-rooted store so parallel runs never collide on a
/// shared `Documents/Saves/<gameID>` slot.
private func tempStore() -> SaveStorage {
  SaveStorage(root: FileManager.default.temporaryDirectory
    .appendingPathComponent("saves-\(UUID().uuidString)", isDirectory: true))
}

@Test("a written save slot reads back byte-for-byte")
func saveRoundTrips() {
  let store = tempStore()
  let bytes = Data([0x46, 0x4f, 0x52, 0x4d, 0x00, 0x01, 0xff])
  store.write(gameID: "zork", data: bytes)
  #expect(store.read(gameID: "zork") == bytes)
}

@Test("reading an unwritten slot is nil and exists is false")
func saveAbsentIsNil() {
  let store = tempStore()
  #expect(store.read(gameID: "zork") == nil)
  #expect(store.exists(gameID: "zork") == false)
}

@Test("exists tracks write then delete")
func saveExistsLifecycle() {
  let store = tempStore()
  store.write(gameID: "zork", data: Data([1, 2, 3]))
  #expect(store.exists(gameID: "zork"))
  store.delete(gameID: "zork")
  #expect(store.exists(gameID: "zork") == false)
  #expect(store.read(gameID: "zork") == nil)
}

@Test("a later write overwrites the single slot")
func saveOverwrites() {
  let store = tempStore()
  store.write(gameID: "zork", data: Data([1, 2, 3]))
  store.write(gameID: "zork", data: Data([9, 8]))
  #expect(store.read(gameID: "zork") == Data([9, 8]))
}

@Test("save slots are isolated per game")
func saveIsolatedPerGame() {
  let store = tempStore()
  store.write(gameID: "zork", data: Data([1]))
  store.write(gameID: "curses", data: Data([2]))
  #expect(store.read(gameID: "zork") == Data([1]))
  #expect(store.read(gameID: "curses") == Data([2]))
}

@Test("gameID derives from the story filename and sanitizes separators")
func gameIDSanitizes() {
  #expect(SaveStorage.gameID(for: URL(fileURLWithPath: "/tmp/Mini Zork.z3")) == "Mini Zork")
  #expect(SaveStorage.gameID(for: URL(fileURLWithPath: "/a/b/curses.z5")) == "curses")
}
