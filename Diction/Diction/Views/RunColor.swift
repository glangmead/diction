import Foundation

/// An sRGB colour parsed from a RemGlk style's CSS `color` string, with a
/// readability lift for the app's dark transcript background. Pure value type
/// (no SwiftUI) so the parsing and lift math stay unit-testable.
nonisolated struct RunColor: Equatable, Sendable {
  var red: Double
  var green: Double
  var blue: Double

  /// Parse a CSS colour: `#rgb` or `#rrggbb` (with or without the `#`), or one
  /// of a small set of named colours. Returns nil for anything else.
  static func parse(css raw: String) -> RunColor? {
    let string = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !string.isEmpty else { return nil }
    if string.hasPrefix("#") { return hex(String(string.dropFirst())) }
    if let named = named[string] { return named }
    return hex(string)  // bare hex like "0000ff"
  }

  /// Perceptual luma (Rec. 709 weights), 0...1.
  var luma: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

  /// Nudge a game-specified colour so it stays readable against the transcript
  /// background, preserving hue. On a **dark** background, lift dim colours
  /// toward white up to `threshold` luma; on a **light** background, darken
  /// bright colours toward black down to it. Colours already on the readable
  /// side pass through. Luma is linear in the channels, so each blend lands
  /// exactly on the threshold.
  func legible(onDark: Bool, threshold: Double = 0.5) -> RunColor {
    if onDark {
      guard luma < threshold else { return self }
      let amount = (threshold - luma) / (1 - luma)
      return RunColor(
        red: red + (1 - red) * amount,
        green: green + (1 - green) * amount,
        blue: blue + (1 - blue) * amount
      )
    } else {
      guard luma > threshold else { return self }
      let scale = threshold / luma
      return RunColor(red: red * scale, green: green * scale, blue: blue * scale)
    }
  }

  // MARK: - Parsing helpers

  private static func hex(_ raw: String) -> RunColor? {
    let chars = Array(raw)
    func channel(_ slice: String) -> Double? {
      guard let value = Int(slice, radix: 16) else { return nil }
      return Double(value) / 255
    }
    switch chars.count {
    case 3:
      guard let red = channel(String([chars[0], chars[0]])),
            let green = channel(String([chars[1], chars[1]])),
            let blue = channel(String([chars[2], chars[2]])) else { return nil }
      return RunColor(red: red, green: green, blue: blue)
    case 6:
      guard let red = channel(String(chars[0...1])),
            let green = channel(String(chars[2...3])),
            let blue = channel(String(chars[4...5])) else { return nil }
      return RunColor(red: red, green: green, blue: blue)
    default:
      return nil
    }
  }

  /// The CSS named colours RemGlk realistically emits. Unknown names fall back
  /// to the run's default colour rather than guessing.
  private static let named: [String: RunColor] = [
    "black": RunColor(red: 0, green: 0, blue: 0),
    "white": RunColor(red: 1, green: 1, blue: 1),
    "red": RunColor(red: 1, green: 0, blue: 0),
    "green": RunColor(red: 0, green: 0.502, blue: 0),
    "blue": RunColor(red: 0, green: 0, blue: 1),
    "yellow": RunColor(red: 1, green: 1, blue: 0),
    "cyan": RunColor(red: 0, green: 1, blue: 1),
    "magenta": RunColor(red: 1, green: 0, blue: 1),
    "gray": RunColor(red: 0.502, green: 0.502, blue: 0.502),
    "grey": RunColor(red: 0.502, green: 0.502, blue: 0.502)
  ]
}
