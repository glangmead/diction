import Testing
@testable import Diction

@Suite("Run colour")
struct RunColorTests {
  @Test("Parses 6- and 3-digit hex, with or without #")
  func parsesHex() {
    #expect(RunColor.parse(css: "#0000FF") == RunColor(red: 0, green: 0, blue: 1))
    #expect(RunColor.parse(css: "0000ff") == RunColor(red: 0, green: 0, blue: 1))
    #expect(RunColor.parse(css: "#fff") == RunColor(red: 1, green: 1, blue: 1))
    #expect(RunColor.parse(css: "#000") == RunColor(red: 0, green: 0, blue: 0))
  }

  @Test("Parses a few named colours; unknown strings are nil")
  func parsesNamed() {
    #expect(RunColor.parse(css: "white") == RunColor(red: 1, green: 1, blue: 1))
    #expect(RunColor.parse(css: "black") == RunColor(red: 0, green: 0, blue: 0))
    #expect(RunColor.parse(css: "not-a-colour") == nil)
    #expect(RunColor.parse(css: "") == nil)
  }

  @Test("Luma uses perceptual weights (green heaviest, blue lightest)")
  func luma() {
    #expect(RunColor(red: 1, green: 1, blue: 1).luma == 1)
    #expect(RunColor(red: 0, green: 0, blue: 0).luma == 0)
    #expect(RunColor(red: 0, green: 1, blue: 0).luma > RunColor(red: 0, green: 0, blue: 1).luma)
  }

  @Test("On a dark background, dim colours lift to the threshold and keep their hue")
  func legibleOnDark() {
    let threshold = 0.5
    let black = RunColor(red: 0, green: 0, blue: 0).legible(onDark: true, threshold: threshold)
    #expect(abs(black.luma - threshold) < 0.0001)

    let blue = RunColor(red: 0, green: 0, blue: 1).legible(onDark: true, threshold: threshold)
    #expect(abs(blue.luma - threshold) < 0.0001)
    #expect(blue.blue > blue.red)  // still bluish

    let bright = RunColor(red: 0.9, green: 0.9, blue: 0.9)
    #expect(bright.legible(onDark: true, threshold: threshold) == bright)  // already readable
  }

  @Test("On a light background, bright colours darken to the threshold and keep their hue")
  func legibleOnLight() {
    let threshold = 0.5
    let white = RunColor(red: 1, green: 1, blue: 1).legible(onDark: false, threshold: threshold)
    #expect(abs(white.luma - threshold) < 0.0001)

    let yellow = RunColor(red: 1, green: 1, blue: 0).legible(onDark: false, threshold: threshold)
    #expect(abs(yellow.luma - threshold) < 0.0001)
    #expect(yellow.blue < yellow.red)  // still yellowish

    let dim = RunColor(red: 0.1, green: 0.1, blue: 0.1)
    #expect(dim.legible(onDark: false, threshold: threshold) == dim)  // already readable
  }
}
