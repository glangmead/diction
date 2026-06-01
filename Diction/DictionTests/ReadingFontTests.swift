import Testing
import SwiftUI
@testable import Diction

// Contract tests for the flowing-text font config. The enums are config-like, so
// these lock the intent (design mapping, ascending sizes, medium == unscaled)
// against accidental regressions rather than driving the implementation.

@Suite("Reading font settings")
struct ReadingFontTests {
  @Test("Typefaces map to the matching system font designs")
  func typefaceDesigns() {
    #expect(ReadingTypeface.sansSerif.design == .default)
    #expect(ReadingTypeface.serif.design == .serif)
    #expect(ReadingTypeface.monospaced.design == .monospaced)
  }

  @Test("There are exactly three typefaces")
  func typefaceCount() {
    #expect(ReadingTypeface.allCases.count == 3)
  }

  @Test("Five size steps; medium is unscaled and the multipliers strictly ascend")
  func sizeSteps() {
    let multipliers = ReadingTextSize.allCases.map(\.multiplier)
    #expect(multipliers.count == 5)
    #expect(ReadingTextSize.medium.multiplier == 1.0)
    #expect(zip(multipliers, multipliers.dropFirst()).allSatisfy { $0.0 < $0.1 })
  }
}
