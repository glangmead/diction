import Testing
import Foundation
@testable import Diction

@Suite("Story file naming and hashing")
struct StoryFileNamingTests {
  // MARK: - uniqueFilename

  @Test("a free name is used unchanged")
  func freeName() {
    #expect(StoryFileManager.uniqueFilename(base: "amfv.z5", existing: []) == "amfv.z5")
  }

  @Test("a taken name gets a macOS-style ' (2)' suffix on the stem, keeping the extension")
  func firstCollision() {
    #expect(
      StoryFileManager.uniqueFilename(base: "amfv.z5", existing: ["amfv.z5"]) == "amfv (2).z5"
    )
  }

  @Test("the suffix counts up past existing numbered copies")
  func countsUp() {
    let existing: Set<String> = ["amfv.z5", "amfv (2).z5", "amfv (3).z5"]
    #expect(StoryFileManager.uniqueFilename(base: "amfv.z5", existing: existing) == "amfv (4).z5")
  }

  @Test("an extensionless name suffixes the whole name")
  func noExtension() {
    #expect(StoryFileManager.uniqueFilename(base: "story", existing: ["story"]) == "story (2)")
  }

  // MARK: - sha256

  @Test("sha256 of data matches the known digest for \"abc\"")
  func knownDigest() {
    let data = Data("abc".utf8)
    #expect(
      StoryFileManager.sha256(of: data)
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  @Test("two files with identical bytes hash equal; one differing byte does not")
  func fileHashing() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("storyhash-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let a = dir.appendingPathComponent("a.bin")
    let b = dir.appendingPathComponent("b.bin")
    let c = dir.appendingPathComponent("c.bin")
    try Data([0x01, 0x02, 0x03]).write(to: a)
    try Data([0x01, 0x02, 0x03]).write(to: b)
    try Data([0x01, 0x02, 0x04]).write(to: c)

    let hashA = StoryFileManager.sha256(ofFileAt: a)
    #expect(hashA != nil)
    #expect(hashA == StoryFileManager.sha256(ofFileAt: b))
    #expect(hashA != StoryFileManager.sha256(ofFileAt: c))
  }
}
