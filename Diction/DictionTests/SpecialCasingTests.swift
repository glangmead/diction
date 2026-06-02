import Testing
@testable import Diction

// All-caps "ZORK" was spelled out (Z-O-R-K) by the initialism heuristic;
// title-casing it whole-word routes it to normal word pronunciation.

@MainActor
@Suite("Special casing")
struct SpecialCasingTests {
  @Test("All-caps ZORK becomes title case so it's said as a word")
  func zork() {
    #expect(KokoroPhonemizer.applySpecialCasing("ZORK") == "Zork")
    #expect(KokoroPhonemizer.applySpecialCasing("Welcome to ZORK!") == "Welcome to Zork!")
  }

  @Test("Other casings and non-whole-word matches are left alone")
  func leavesOthers() {
    #expect(KokoroPhonemizer.applySpecialCasing("Zork") == "Zork")
    #expect(KokoroPhonemizer.applySpecialCasing("zork") == "zork")
    #expect(KokoroPhonemizer.applySpecialCasing("ZORKMID") == "ZORKMID")
  }
}
