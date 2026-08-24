import Testing
import Foundation
@testable import Diction

@Suite("Story metadata extraction & store")
struct StoryMetadataTests {
  // MARK: - Version labels

  @Test("Z-machine header yields a Release + Serial label")
  func zMachineVersion() {
    var header = [UInt8](repeating: 0, count: 32)
    header[0] = 5                      // version
    header[2] = 0x00                   // release hi
    header[3] = 0x16                   // release lo → 22
    let serial: [UInt8] = Array("870506".utf8)
    for (offset, byte) in serial.enumerated() { header[0x12 + offset] = byte }
    #expect(StoryMetadataExtractor.zMachineVersionLabel(header) == "Release 22 · Serial 870506")
  }

  @Test("Glulx header yields a dotted version label")
  func glulxVersion() {
    let header: [UInt8] = [0x47, 0x6C, 0x75, 0x6C, 0x00, 0x03, 0x01, 0x01]  // "Glul" + 3.1.1
    #expect(StoryMetadataExtractor.glulxVersionLabel(header) == "Glulx 3.1.1")
  }

  @Test("short headers return no version label")
  func shortHeaders() {
    #expect(StoryMetadataExtractor.zMachineVersionLabel([5, 0, 0]) == nil)
    #expect(StoryMetadataExtractor.glulxVersionLabel([0x47, 0x6C]) == nil)
  }

  // MARK: - iFiction XML

  @Test("iFiction bibliographic fields are parsed")
  func iFiction() {
    let xml = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <ifindex version="1.0" xmlns="http://babel.ifarchive.org/protocol/iFiction/">
      <story>
        <bibliographic>
          <title>Ballyhoo</title>
          <author>Jeff O'Neill</author>
          <language>en</language>
          <firstpublished>1986</firstpublished>
          <headline>An Interactive Comedy</headline>
        </bibliographic>
      </story>
    </ifindex>
    """.utf8)
    let meta = StoryMetadataExtractor.parseIFiction(xml)
    #expect(meta.title == "Ballyhoo")
    #expect(meta.author == "Jeff O'Neill")
    #expect(meta.year == "1986")
    #expect(meta.headline == "An Interactive Comedy")
  }

  // MARK: - merging

  @Test("supplemental fields win, but the file's version label is kept")
  func merging() {
    let file = StoryMetadata(versionLabel: "Release 22 · Serial 870506")
    let supplemental = StoryMetadata(
      title: "Ballyhoo", author: "Jeff O'Neill", year: "1986",
      headline: "An Interactive Comedy", versionLabel: "ignored"
    )
    let merged = file.merging(supplemental)
    #expect(merged.title == "Ballyhoo")
    #expect(merged.author == "Jeff O'Neill")
    #expect(merged.year == "1986")
    #expect(merged.headline == "An Interactive Comedy")
    #expect(merged.versionLabel == "Release 22 · Serial 870506")
  }

  @Test("merging with nil returns the receiver unchanged")
  func mergingNil() {
    let file = StoryMetadata(title: "X", versionLabel: "Glulx 3.1.1")
    #expect(file.merging(nil) == file)
  }

  // MARK: - Bare-file extraction

  @Test("a bare Z-machine file extracts a version label and no title or cover")
  func bareZMachineFile() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("meta-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    var bytes = [UInt8](repeating: 0, count: 64)
    bytes[0] = 5
    bytes[3] = 0x16  // release 22
    for (offset, byte) in Array("870506".utf8).enumerated() { bytes[0x12 + offset] = byte }
    let url = dir.appendingPathComponent("game.z5")
    try Data(bytes).write(to: url)

    let result = StoryMetadataExtractor.fileMetadata(forFileAt: url)
    #expect(result.metadata.versionLabel == "Release 22 · Serial 870506")
    #expect(result.metadata.title == nil)
    #expect(result.coverImage == nil)
  }

  // MARK: - Blorb extraction

  @Test("a Blorb yields its iFiction title/author and the cover the Fspc points to")
  func blorbExtraction() throws {
    func beUInt32(_ value: Int) -> [UInt8] {
      [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
       UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
    func chunk(_ type: String, _ payload: [UInt8]) -> [UInt8] {
      var out = Array(type.utf8) + beUInt32(payload.count) + payload
      if payload.count % 2 == 1 { out.append(0) }  // IFF even-length padding
      return out
    }

    let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xAA, 0xBB]
    let xml: [UInt8] = Array("""
    <ifindex xmlns="http://babel.ifarchive.org/protocol/iFiction/"><story>\
    <bibliographic><title>Lost Pig</title><author>Admiral Jota</author>\
    </bibliographic></story></ifindex>
    """.utf8)

    let ifmd = chunk("IFmd", xml)
    let fspc = chunk("Fspc", beUInt32(1))            // cover = Pict resource #1
    let ridxLen = 24                                  // "RIdx"+len + count + one 12-byte entry
    let pngStart = 12 + ridxLen + ifmd.count + fspc.count
    let ridx = chunk("RIdx", beUInt32(1) + Array("Pict".utf8) + beUInt32(1) + beUInt32(pngStart))
    let pict = chunk("PNG ", png)

    let body = Array("IFRS".utf8) + ridx + ifmd + fspc + pict
    let blorb = Array("FORM".utf8) + beUInt32(body.count) + body

    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("blorb-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("game.zblorb")
    try Data(blorb).write(to: url)

    let result = StoryMetadataExtractor.fileMetadata(forFileAt: url)
    #expect(result.metadata.title == "Lost Pig")
    #expect(result.metadata.author == "Admiral Jota")
    #expect(result.coverImage == Data(png))
  }

  // MARK: - Bundled record

  @Test("the bundled All Things Devours carries its baked-in IFDB metadata")
  func bundledMetadata() {
    let devours = StoryFileManager.bundledGames.first { $0.name == "devours" }
    let meta = devours?.metadata
    #expect(meta?.title == "All Things Devours")
    #expect(meta?.author == "half sick of shadows")
    #expect(meta?.year == "2004")
    #expect(meta?.headline == "Time Travel")
  }

  // MARK: - Store round-trip

  @Test("the store persists metadata and the cover across instances, and removes both")
  func storeRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("metastore-\(UUID().uuidString)", isDirectory: true)
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])

    let store = StoryMetadataStore(directory: dir)
    let stored = store.setMetadata(
      StoryMetadata(title: "Ballyhoo", versionLabel: "Release 22 · Serial 870506"),
      coverImage: png,
      for: "Ballyhoo.z5"
    )
    #expect(stored.coverFilename?.hasSuffix(".png") == true)

    // A fresh instance reads the same directory.
    let reloaded = StoryMetadataStore(directory: dir)
    let meta = try #require(reloaded.metadata(for: "Ballyhoo.z5"))
    #expect(meta.title == "Ballyhoo")
    #expect(meta == stored)
    let coverURL = try #require(reloaded.coverURL(for: meta))
    #expect(try Data(contentsOf: coverURL) == png)

    reloaded.remove(for: "Ballyhoo.z5")
    #expect(reloaded.metadata(for: "Ballyhoo.z5") == nil)
    #expect(FileManager.default.fileExists(atPath: coverURL.path) == false)
  }
}
