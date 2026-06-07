import Foundation

/// Reads a Blorb (`FORM`…`IFRS`) resource container: walks its top-level IFF chunks,
/// parses the `RIdx` resource index, and resolves the cover image and the executable.
/// `FormatDetector` handles format identification; this handles richer extraction.
struct BlorbReader {
  /// One `RIdx` entry: a resource's usage (`Pict`/`Snd `/`Exec`/`Data`), its number,
  /// and the absolute file offset of its chunk.
  struct Resource {
    let usage: String
    let number: Int
    let start: Int
  }

  private let bytes: [UInt8]

  /// Fails unless `data` opens with the `FORM`…`IFRS` Blorb preamble.
  init?(_ data: Data) {
    let bytes = [UInt8](data)
    guard bytes.count >= 12,
      Array(bytes[0..<4]) == Array("FORM".utf8),
      Array(bytes[8..<12]) == Array("IFRS".utf8)
    else { return nil }
    self.bytes = bytes
  }

  /// Payload of the first top-level chunk of `type` (e.g. `IFmd`, `Fspc`).
  func chunk(ofType type: String) -> Data? {
    let wanted = Array(type.utf8)
    var offset = 12
    while offset + 8 <= bytes.count {
      let length = beUInt32(at: offset + 4)
      let dataStart = offset + 8
      let dataEnd = min(dataStart + Int(length), bytes.count)
      if Array(bytes[offset..<offset + 4]) == wanted {
        return Data(bytes[dataStart..<dataEnd])
      }
      offset += 8 + Int(length) + (Int(length) % 2)  // chunks pad to even length
    }
    return nil
  }

  /// The `RIdx` resource entries.
  func resourceIndex() -> [Resource] {
    guard let ridx = chunk(ofType: "RIdx") else { return [] }
    let data = [UInt8](ridx)
    guard data.count >= 4 else { return [] }
    let count = Int(Self.beUInt32(data, at: 0))
    var entries: [Resource] = []
    for index in 0..<count {
      let base = 4 + index * 12
      guard base + 12 <= data.count else { break }
      let usage = String(bytes: data[base..<base + 4], encoding: .ascii) ?? ""
      entries.append(Resource(
        usage: usage,
        number: Int(Self.beUInt32(data, at: base + 4)),
        start: Int(Self.beUInt32(data, at: base + 8))
      ))
    }
    return entries
  }

  /// The cover image bytes: the `Pict` resource named by `Fspc` (frontispiece), or the
  /// first `Pict` if there's no `Fspc`. Returns the resource chunk's payload (a PNG or
  /// JPEG), or nil when the blorb has no pictures.
  func coverImage() -> Data? {
    let index = resourceIndex()
    let resourceNumber: Int
    if let fspc = chunk(ofType: "Fspc"), fspc.count >= 4 {
      resourceNumber = Int(Self.beUInt32([UInt8](fspc), at: 0))
    } else if let firstPict = index.first(where: { $0.usage == "Pict" }) {
      resourceNumber = firstPict.number
    } else {
      return nil
    }
    guard let pict = index.first(where: { $0.usage == "Pict" && $0.number == resourceNumber }),
      let resource = chunkAt(offset: pict.start)
    else { return nil }
    return resource.data
  }

  /// The executable: whether it's Glulx, and the file offset where the story bytes
  /// begin (past the chunk's 4-byte type + 4-byte length). Used to read the version.
  func executable() -> (isGlulx: Bool, storyStart: Int)? {
    guard let exec = resourceIndex().first(where: { $0.usage == "Exec" }),
      let resource = chunkAt(offset: exec.start)
    else { return nil }
    return (resource.type == "GLUL", exec.start + 8)
  }

  // MARK: - Internals

  /// The chunk located at an absolute file offset (as named by an `RIdx` entry):
  /// its 4-char type and payload.
  private func chunkAt(offset: Int) -> (type: String, data: Data)? {
    guard offset >= 0, offset + 8 <= bytes.count else { return nil }
    let type = String(bytes: bytes[offset..<offset + 4], encoding: .ascii) ?? ""
    let length = beUInt32(at: offset + 4)
    let start = offset + 8
    let end = min(start + Int(length), bytes.count)
    return (type, Data(bytes[start..<end]))
  }

  private func beUInt32(at offset: Int) -> UInt32 { Self.beUInt32(bytes, at: offset) }

  private static func beUInt32(_ source: [UInt8], at offset: Int) -> UInt32 {
    guard offset + 4 <= source.count else { return 0 }
    return (UInt32(source[offset]) << 24) | (UInt32(source[offset + 1]) << 16)
      | (UInt32(source[offset + 2]) << 8) | UInt32(source[offset + 3])
  }
}
