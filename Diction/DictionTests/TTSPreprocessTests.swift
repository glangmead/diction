import Testing
@testable import Diction

@Suite("TTS pre-G2P transforms")
struct TTSPreprocessTests {
  @Test("replace rule swaps the matched text")
  func replaceRule() {
    let rule = TextRule(id: "zork", match: #"\bZORK\b"#, action: .replace, with: "Zork")
    #expect(rule.apply(to: "play ZORK now") == "play Zork now")
  }

  @Test("spaceDigits splits a long digit run; commas and decimals are untouched")
  func spaceDigitsRule() {
    let rule = TextRule(id: "digits", match: #"(?<![\d,])\d{4,}(?![\d,])"#, action: .spaceDigits)
    #expect(rule.apply(to: "code 123456 now") == "code 1 2 3 4 5 6 now")
    #expect(rule.apply(to: "1,234 apples") == "1,234 apples")
    #expect(rule.apply(to: "pi is 3.14") == "pi is 3.14")
  }

  @Test("ipa pronunciation wraps whole-word matches in the in-band override syntax")
  func ipaPronunciation() {
    let tts = TTSInterventions(
      pronunciations: [PronEntry(word: "copied", ipa: "kˈɑpid")], textRules: [], pausePolicy: nil)
    #expect(tts.preprocessText("I copied it") == "I [copied](/kˈɑpid/) it")
  }

  @Test("say pronunciation substitutes a respelling")
  func sayPronunciation() {
    let tts = TTSInterventions(
      pronunciations: [PronEntry(word: "PRSO", say: "parser object")], textRules: [], pausePolicy: nil)
    #expect(tts.preprocessText("type PRSO") == "type parser object")
  }

  @Test("textRules run before pronunciations, in array order")
  func combinedOrder() {
    let tts = TTSInterventions(
      pronunciations: [PronEntry(word: "Zork", ipa: "zˈɔɹk")],
      textRules: [TextRule(id: "zork", match: #"\bZORK\b"#, action: .replace, with: "Zork")],
      pausePolicy: nil)
    // ZORK → Zork (rule), then Zork → wrapped (pronunciation).
    #expect(tts.preprocessText("play ZORK") == "play [Zork](/zˈɔɹk/)")
  }

  @Test("empty interventions pass text through unchanged")
  func passthrough() {
    #expect(TTSInterventions.empty.preprocessText("nothing to do here") == "nothing to do here")
  }
}
