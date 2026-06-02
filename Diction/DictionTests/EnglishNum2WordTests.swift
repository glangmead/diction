import Testing
import Foundation
@testable import Diction

// The num2words port dropped "twenty": `midNumWords` lacked (20, "twenty"), so
// numbers 21–29 (and any number containing them) lost the tens word — "24" spoke
// as "four", "871124" as if the tens digit were 0.

@MainActor
@Suite("Number to words")
struct EnglishNum2WordTests {
  let n2w = EnglishNum2Word()

  @Test("Numbers in the twenties keep their tens word")
  func twenties() {
    #expect(n2w.convert(Decimal(20), to: .decimal) == "twenty")
    #expect(n2w.convert(Decimal(21), to: .decimal) == "twenty-one")
    #expect(n2w.convert(Decimal(24), to: .decimal) == "twenty-four")
    #expect(n2w.convert(Decimal(29), to: .decimal) == "twenty-nine")
  }

  @Test("Twenties survive inside larger numbers")
  func twentiesInLargerNumbers() {
    #expect(n2w.convert(Decimal(124), to: .decimal) == "one hundred and twenty-four")
    #expect(n2w.convert(Decimal(871124), to: .decimal).contains("twenty-four"))
  }

  @Test("Other tens still work (regression guard)")
  func otherTens() {
    #expect(n2w.convert(Decimal(34), to: .decimal) == "thirty-four")
    #expect(n2w.convert(Decimal(99), to: .decimal) == "ninety-nine")
    #expect(n2w.convert(Decimal(4), to: .decimal) == "four")
  }
}
