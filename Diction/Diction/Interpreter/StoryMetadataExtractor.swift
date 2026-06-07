import Foundation

/// Extracts `StoryMetadata` from a story file. Bare Z-machine/Glulx files yield only
/// a version label; Blorb containers additionally yield title/author/year/headline
/// (from the `IFmd` iFiction record) and cover art (from `Fspc`→`Pict`).
enum StoryMetadataExtractor {
  /// "Release 22 · Serial 870506" from a Z-machine story header: release is the
  /// big-endian word at 0x02, serial the six ASCII bytes at 0x12.
  static func zMachineVersionLabel(_ header: [UInt8]) -> String? {
    guard header.count >= 0x18 else { return nil }
    let release = (UInt16(header[2]) << 8) | UInt16(header[3])
    guard let serial = String(bytes: header[0x12..<0x18], encoding: .ascii) else { return nil }
    return "Release \(release) · Serial \(serial)"
  }

  /// "Glulx 3.1.1" from a Glulx header: the version is the big-endian word at 0x04
  /// (major), then the two bytes at 0x06/0x07 (minor, sub).
  static func glulxVersionLabel(_ header: [UInt8]) -> String? {
    guard header.count >= 8 else { return nil }
    let major = (UInt16(header[4]) << 8) | UInt16(header[5])
    return "Glulx \(major).\(header[6]).\(header[7])"
  }

  /// Parse a Treaty-of-Babel iFiction record's `<bibliographic>` block.
  static func parseIFiction(_ xml: Data) -> StoryMetadata {
    IFictionParser().parse(xml)
  }

  /// File-derived metadata plus the embedded cover image bytes, if any. Bare files
  /// resolve only a version label; Blorbs additionally yield iFiction fields and cover.
  static func fileMetadata(forFileAt url: URL) -> (metadata: StoryMetadata, coverImage: Data?) {
    guard let data = try? Data(contentsOf: url) else { return (StoryMetadata(), nil) }
    let bytes = [UInt8](data)

    if let reader = BlorbReader(data) {
      var meta = reader.chunk(ofType: "IFmd").map(parseIFiction) ?? StoryMetadata()
      if let exec = reader.executable() {
        let story = Array(bytes[min(exec.storyStart, bytes.count)...])
        meta.versionLabel = exec.isGlulx ? glulxVersionLabel(story) : zMachineVersionLabel(story)
      }
      return (meta, reader.coverImage())
    }

    var meta = StoryMetadata()
    if let first = bytes.first, (1...8).contains(first) {
      meta.versionLabel = zMachineVersionLabel(bytes)
    } else if bytes.count >= 4, Array(bytes[0..<4]) == [0x47, 0x6C, 0x75, 0x6C] {  // "Glul"
      meta.versionLabel = glulxVersionLabel(bytes)
    }
    return (meta, nil)
  }
}

/// Minimal `XMLParser` delegate for the iFiction `<bibliographic>` block. Namespace
/// processing stays off, so element names arrive as their local names (`title`, …).
private final class IFictionParser: NSObject, XMLParserDelegate {
  private var meta = StoryMetadata()
  private var current = ""
  private var inBibliographic = false

  func parse(_ data: Data) -> StoryMetadata {
    let parser = XMLParser(data: data)
    parser.delegate = self
    parser.parse()
    return meta
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    if elementName == "bibliographic" { inBibliographic = true }
    current = ""
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    current += string
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName: String?
  ) {
    let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = text.isEmpty ? nil : text
    if inBibliographic {
      switch elementName {
      case "title": meta.title = value
      case "author": meta.author = value
      case "firstpublished": meta.year = value.map { String($0.prefix(4)) }
      case "headline": meta.headline = value
      case "bibliographic": inBibliographic = false
      default: break
      }
    }
    current = ""
  }
}
