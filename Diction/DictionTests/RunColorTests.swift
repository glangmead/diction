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

  @Test("Dark colours lift to the floor and keep their hue; bright colours pass through")
  func lift() {
    let floor = 0.5
    let liftedBlack = RunColor(red: 0, green: 0, blue: 0).liftedForDarkBackground(minimumLuma: floor)
    #expect(abs(liftedBlack.luma - floor) < 0.0001)

    let liftedBlue = RunColor(red: 0, green: 0, blue: 1).liftedForDarkBackground(minimumLuma: floor)
    #expect(abs(liftedBlue.luma - floor) < 0.0001)
    #expect(liftedBlue.blue > liftedBlue.red)  // still bluish

    let bright = RunColor(red: 0.9, green: 0.9, blue: 0.9)
    #expect(bright.liftedForDarkBackground(minimumLuma: floor) == bright)
  }
}
