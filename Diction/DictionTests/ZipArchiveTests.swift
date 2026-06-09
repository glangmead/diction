import Compression
import Foundation
import Testing
@testable import Diction

@Suite("ZIP story extraction")
struct ZipArchiveTests {
  @Test("Extracts a DEFLATE-compressed story file, skipping non-story entries")
  func extractsDeflated() throws {
    let story = Data((0..<800).map { UInt8($0 % 13) })   // compressible, so DEFLATE engages
    let zip = makeZip([
      ZipEntry(name: "readme.txt", data: Data("hello there".utf8), compress: .deflate),
      ZipEntry(name: "museo.ulx", data: story, compress: .deflate)
    ])
    let extracted = try ZipStoryExtractor.storyFile(in: zip)
    #expect(extracted.name == "museo.ulx")
    #expect(extracted.data == story)
  }

  @Test("Extracts a stored (uncompressed) story file")
  func extractsStored() throws {
    let story = Data(repeating: 0xAB, count: 500)
    let zip = makeZip([ZipEntry(name: "game.z5", data: story, compress: .stored)])
    let extracted = try ZipStoryExtractor.storyFile(in: zip)
    #expect(extracted.name == "game.z5")
    #expect(extracted.data == story)
  }

  @Test("Extracts a story file nested in a subdirectory by its base name")
  func extractsNested() throws {
    let story = Data((0..<400).map { UInt8($0 % 7) })
    let zip = makeZip([ZipEntry(name: "Glulx/museo.gblorb", data: story, compress: .deflate)])
    let extracted = try ZipStoryExtractor.storyFile(in: zip)
    #expect(extracted.name == "museo.gblorb")
    #expect(extracted.data == story)
  }

  @Test("Picks the largest story file when several are present")
  func picksLargest() throws {
    let small = Data(repeating: 1, count: 50)
    let big = Data(repeating: 2, count: 5000)
    let zip = makeZip([
      ZipEntry(name: "demo.z5", data: small, compress: .stored),
      ZipEntry(name: "full.z5", data: big, compress: .stored)
    ])
    let extracted = try ZipStoryExtractor.storyFile(in: zip)
    #expect(extracted.name == "full.z5")
    #expect(extracted.data == big)
  }

  @Test("Throws when the zip holds no story file")
  func noStory() {
    let zip = makeZip([
      ZipEntry(name: "notes.txt", data: Data("x".utf8), compress: .stored),
      ZipEntry(name: "cover.jpg", data: Data([0xFF, 0xD8]), compress: .stored)
    ])
    #expect(throws: ZipStoryExtractor.ExtractError.self) {
      try ZipStoryExtractor.storyFile(in: zip)
    }
  }

  @Test("Rejects bytes that aren't a zip")
  func notAZip() {
    #expect(throws: ZipArchive.ZipError.self) {
      try ZipStoryExtractor.storyFile(in: Data("not a zip at all".utf8))
    }
  }

  // MARK: - Minimal in-memory ZIP writer (test fixture only)

  private enum Compress { case stored, deflate }
  private struct ZipEntry { let name: String; let data: Data; let compress: Compress }
  private struct Prepared { let name: [UInt8]; let stored: Data; let payload: Data; let method: UInt16 }

  /// Builds a valid-enough ZIP (local headers + central directory + EOCD). CRCs are
  /// left zero — the reader doesn't verify them — and sizes are written into the
  /// central directory, which is what `ZipArchive` reads.
  private func makeZip(_ entries: [ZipEntry]) -> Data {
    let prepared = entries.map(prepare)
    var local = Data()
    var offsets: [Int] = []
    for item in prepared {
      offsets.append(local.count)
      local.append(localHeader(item))
    }
    let centralStart = local.count
    var central = Data()
    for (index, item) in prepared.enumerated() {
      central.append(centralHeader(item, localOffset: offsets[index]))
    }
    var eocd = Data()
    appendU32(0x0605_4b50, &eocd)
    appendU16(0, &eocd); appendU16(0, &eocd)         // disk numbers
    appendU16(UInt16(prepared.count), &eocd); appendU16(UInt16(prepared.count), &eocd)
    appendU32(UInt32(central.count), &eocd)
    appendU32(UInt32(centralStart), &eocd)
    appendU16(0, &eocd)                              // comment length
    return local + central + eocd
  }

  private func prepare(_ entry: ZipEntry) -> Prepared {
    let nameBytes = Array(entry.name.utf8)
    if entry.compress == .deflate, let deflated = rawDeflate(entry.data) {
      return Prepared(name: nameBytes, stored: entry.data, payload: deflated, method: 8)
    }
    return Prepared(name: nameBytes, stored: entry.data, payload: entry.data, method: 0)
  }

  private func localHeader(_ item: Prepared) -> Data {
    var data = Data()
    appendU32(0x0403_4b50, &data)
    appendU16(20, &data); appendU16(0, &data)        // version needed, flags
    appendU16(item.method, &data)
    appendU16(0, &data); appendU16(0, &data)         // mod time / date
    appendU32(0, &data)                              // crc-32 (ignored by the reader)
    appendU32(UInt32(item.payload.count), &data)     // compressed size
    appendU32(UInt32(item.stored.count), &data)      // uncompressed size
    appendU16(UInt16(item.name.count), &data); appendU16(0, &data)  // name / extra len
    data.append(contentsOf: item.name)
    data.append(item.payload)
    return data
  }

  private func centralHeader(_ item: Prepared, localOffset: Int) -> Data {
    var data = Data()
    appendU32(0x0201_4b50, &data)
    appendU16(20, &data); appendU16(20, &data)       // version made by / needed
    appendU16(0, &data)                              // flags
    appendU16(item.method, &data)
    appendU16(0, &data); appendU16(0, &data)         // mod time / date
    appendU32(0, &data)                              // crc-32
    appendU32(UInt32(item.payload.count), &data)
    appendU32(UInt32(item.stored.count), &data)
    appendU16(UInt16(item.name.count), &data)
    appendU16(0, &data); appendU16(0, &data)         // extra / comment len
    appendU16(0, &data); appendU16(0, &data)         // disk number / internal attrs
    appendU32(0, &data)                              // external attrs
    appendU32(UInt32(localOffset), &data)            // local header offset
    data.append(contentsOf: item.name)
    return data
  }

  private func appendU16(_ value: UInt16, _ data: inout Data) {
    data.append(UInt8(value & 0xFF)); data.append(UInt8(value >> 8))
  }

  private func appendU32(_ value: UInt32, _ data: inout Data) {
    data.append(UInt8(value & 0xFF)); data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8((value >> 16) & 0xFF)); data.append(UInt8((value >> 24) & 0xFF))
  }

  /// Raw DEFLATE (RFC 1951) via the Compression framework — the format `ZipArchive`
  /// inflates with `COMPRESSION_ZLIB`.
  private func rawDeflate(_ data: Data) -> Data? {
    guard !data.isEmpty else { return Data() }
    let capacity = data.count + 64
    let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    defer { destination.deallocate() }
    let written = data.withUnsafeBytes { source in
      compression_encode_buffer(
        destination, capacity,
        source.bindMemory(to: UInt8.self).baseAddress!, data.count,
        nil, COMPRESSION_ZLIB)
    }
    return written > 0 ? Data(bytes: destination, count: written) : nil
  }
}
