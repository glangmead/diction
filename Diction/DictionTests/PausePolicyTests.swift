import Testing
@testable import Diction

@Suite("Pause policy")
struct PausePolicyTests {
  // The default must reproduce the old EnglishG2P em-dash transform byte-for-byte,
  // so relocating it out of vendored code doesn't change narration.
  @Test("default turns a flanked em-dash into ';;; '")
  func defaultEmDash() {
    #expect(PausePolicy.default.apply(toPhonemes: "tu — dˈu") == "tu;;; dˈu")
    #expect(PausePolicy.default.apply(toPhonemes: " x — y ") == "x;;; y")
  }

  @Test("default strips a mid-compound em-dash so the word flows")
  func defaultMidCompound() {
    #expect(PausePolicy.default.apply(toPhonemes: "to—do") == "todo")
  }

  @Test("default leaves commas and ordinary text untouched")
  func defaultLeavesCommas() {
    #expect(PausePolicy.default.apply(toPhonemes: "hˈɛlO, wˈɜld") == "hˈɛlO, wˈɜld")
    #expect(PausePolicy.default.apply(toPhonemes: "nˈoʊ pˈɔz") == "nˈoʊ pˈɔz")
  }

  @Test("dash count controls the pause-token run length")
  func dashCount() {
    let policy = PausePolicy(comma: 1, semicolon: 1, colon: 1, dash: 2)
    #expect(policy.apply(toPhonemes: "x — y") == "x;; y")
  }

  @Test("comma count appends extra pause tokens after each comma")
  func commaCount() {
    let policy = PausePolicy(comma: 2, semicolon: 1, colon: 1, dash: 3)
    #expect(policy.apply(toPhonemes: "a, b") == "a,; b")
  }
}
