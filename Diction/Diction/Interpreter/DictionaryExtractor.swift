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
    let zchars = unpackZChars(bytes)

    var result = ""
    var alphabet = 0
    var i = 0
    while i < zchars.count {
      let zchar = zchars[i]
      switch zchar {
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
        if let character = character(forZChar: zchar, alphabet: alphabet) {
          result.append(character)
        }
        alphabet = 0
      }
      i += 1
    }

    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Unpacks 2-byte words into their three 5-bit z-chars, stopping at the word
  /// whose bit 15 marks the end of the entry.
  private static func unpackZChars(_ bytes: [UInt8]) -> [Int] {
    var zchars: [Int] = []
    for offset in stride(from: 0, to: bytes.count - 1, by: 2) {
      let word = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
      zchars.append((word >> 10) & 0x1F)
      zchars.append((word >> 5) & 0x1F)
      zchars.append(word & 0x1F)
      if (word & 0x8000) != 0 {
        break
      }
    }
    return zchars
  }

  /// Alphabet A0 (lowercase). A1 is its uppercase form.
  private static let lowercaseAlphabet = Array("abcdefghijklmnopqrstuvwxyz")
  /// Alphabet A2 (digits and punctuation). Index 0 (z-char 6) is the
  /// 10-bit-ZSCII escape, which dictionary words never use; index 1 is newline.
  private static let punctuationAlphabet = Array(" \n0123456789.,!?_#'\"/\\-:()")

  /// The printable character for a z-char of 6 or more in the given alphabet
  /// (0 = A0 lowercase, 1 = A1 uppercase, 2 = A2 punctuation), or nil when the
  /// index is out of range.
  private static func character(forZChar zchar: Int, alphabet: Int) -> Character? {
    let index = zchar - 6
    switch alphabet {
    case 0 where lowercaseAlphabet.indices.contains(index):
      return lowercaseAlphabet[index]
    case 1 where lowercaseAlphabet.indices.contains(index):
      return Character(lowercaseAlphabet[index].uppercased())
    case 2 where punctuationAlphabet.indices.contains(index):
      return punctuationAlphabet[index]
    default:
      return nil
    }
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
    "verbose", "brief", "score"
  ]
}
