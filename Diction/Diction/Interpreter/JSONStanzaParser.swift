import Foundation

/// Brace-counting scanner that collects bytes until one complete top-level
/// JSON object has been read. Handles quoted strings and escape sequences
/// so braces inside strings don't confuse the depth counter. RemGlk pretty-
/// prints its JSON output with embedded newlines, so we can't simply split
/// on `\n` to find stanza boundaries.
struct JSONStanzaParser {
  private static let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]

  private var depth = 0
  private var inString = false
  private var escape = false
  private var collected = Data()

  mutating func consume(_ byte: UInt8) -> Data? {
    if depth == 0 && collected.isEmpty && Self.whitespace.contains(byte) {
      return nil
    }
    collected.append(byte)

    if inString {
      consumeInString(byte)
      return nil
    }

    switch byte {
    case 0x22: inString = true        // opening quote
    case 0x7B: depth += 1             // {
    case 0x7D:                        // }
      depth -= 1
      if depth == 0 { return collected }
    default: break
    }
    return nil
  }

  private mutating func consumeInString(_ byte: UInt8) {
    if escape {
      escape = false
    } else if byte == 0x5C {          // backslash
      escape = true
    } else if byte == 0x22 {          // closing quote
      inString = false
    }
  }
}
