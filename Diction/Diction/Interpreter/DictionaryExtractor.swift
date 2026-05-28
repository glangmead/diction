import Foundation

/// Extracts the parser dictionary from a Z-machine or Glulx story file.
///
/// The Z-machine dictionary table format is documented in the Z-Machine
/// Standards Document, §13. Each entry begins with the encoded word in
/// Z-characters (4 bytes for versions 1–3, 6 bytes for versions 4+).
/// Glulx doesn't expose its dictionary in a standard way, so we fall back
/// to a set of common IF verbs.
nonisolated enum DictionaryExtractor {
  static func extract(from url: URL) throws -> Set<String> {
    let format = try FormatDetector.detect(url: url)
    switch format {
    case .zMachine:
      return try extractZMachine(from: url)
    case .glulx:
      return commonIFVerbs
    case nil:
      return []
    }
  }

  private static func extractZMachine(from url: URL) throws -> Set<String> {
    let data = try Data(contentsOf: url)
    guard data.count > 0x10 else { return [] }

    let version = Int(data[0])
    let dictAddr = Int(data[0x08]) << 8 | Int(data[0x09])
    guard dictAddr + 4 < data.count else { return [] }

    let numSeparators = Int(data[dictAddr])
    let entryStart = dictAddr + 1 + numSeparators
    guard entryStart + 3 <= data.count else { return [] }

    let entryLength = Int(data[entryStart])
    let numEntries = Int(data[entryStart + 1]) << 8
      | Int(data[entryStart + 2])
    let tableStart = entryStart + 3
    let encodedLength = version <= 3 ? 4 : 6

    var words: Set<String> = []
    for i in 0..<numEntries {
      let offset = tableStart + i * entryLength
      guard offset + encodedLength <= data.count else { break }
      let encoded = Array(data[offset..<(offset + encodedLength)])
      if let word = decodeZCharacters(encoded) {
        words.insert(word.lowercased())
      }
    }
    return words
  }

  /// Decodes Z-characters per the Z-Machine Standards Document §3.
  /// Skips abbreviations (z-chars 1–3) — they aren't used in dictionary entries.
  private static func decodeZCharacters(_ bytes: [UInt8]) -> String? {
    var zchars: [Int] = []

    for i in stride(from: 0, to: bytes.count, by: 2) {
      guard i + 1 < bytes.count else { break }
      let word = Int(bytes[i]) << 8 | Int(bytes[i + 1])
      zchars.append((word >> 10) & 0x1F)
      zchars.append((word >> 5) & 0x1F)
      zchars.append(word & 0x1F)
      // Bit 15 set marks the last word in this entry's encoded form.
      if (word & 0x8000) != 0 {
        break
      }
    }

    let a0 = Array("abcdefghijklmnopqrstuvwxyz")
    let a2 = Array(" \n0123456789.,!?_#'\"/\\-:()")

    var result = ""
    var alphabet = 0
    var i = 0
    while i < zchars.count {
      let zc = zchars[i]
      switch zc {
      case 0:
        result += " "
      case 1, 2, 3:
        // Abbreviation — skip the next z-char (which is the abbreviation index).
        i += 1
      case 4:
        alphabet = 1
      case 5:
        alphabet = 2
      default:
        let index = zc - 6
        switch alphabet {
        case 0:
          if index >= 0, index < a0.count {
            result.append(a0[index])
          }
        case 1:
          if index >= 0, index < a0.count {
            result.append(Character(a0[index].uppercased()))
          }
        case 2:
          if index >= 0, index < a2.count {
            result.append(a2[index])
          }
        default:
          break
        }
        alphabet = 0
      }
      i += 1
    }

    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  static let commonIFVerbs: Set<String> = [
    "look", "examine", "take", "drop", "open", "close",
    "go", "north", "south", "east", "west", "up", "down",
    "northeast", "northwest", "southeast", "southwest",
    "inventory", "save", "restore", "quit", "wait", "again",
    "attack", "give", "put", "read", "enter", "exit",
    "push", "pull", "turn", "search", "unlock", "lock",
    "eat", "drink", "throw", "climb", "jump", "listen",
    "smell", "touch", "talk", "ask", "tell", "show",
    "wear", "remove", "tie", "cut", "dig", "swim",
    "buy", "pray", "sleep", "wake", "yes", "no",
    "verbose", "brief", "score",
  ]
}
