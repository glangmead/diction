import Testing
@testable import Diction

// All-caps "ZORK" was spelled out (Z-O-R-K) by the initialism heuristic;
// title-casing it whole-word routes it to normal word pronunciation. This used to
// be a hardcode (`KokoroPhonemizer.applySpecialCasing`); it's now the bundled
// `zork-casing` textRule, exercised here through `TextRule.apply`.

@Suite("Special casing (zork-casing rule)")
struct SpecialCasingTests {
  private let rule = TextRule(id: "zork-casing", match: #"\bZORK\b"#, action: .replace, with: "Zork")

  @Test("All-caps ZORK becomes title case so it's said as a word")
  func zork() {
    #expect(rule.apply(to: "ZORK") == "Zork")
    #expect(rule.apply(to: "Welcome to ZORK!") == "Welcome to Zork!")
  }

  @Test("Other casings and non-whole-word matches are left alone")
  func leavesOthers() {
    #expect(rule.apply(to: "Zork") == "Zork")
    #expect(rule.apply(to: "zork") == "zork")
    #expect(rule.apply(to: "ZORKMID") == "ZORKMID")
  }
}
