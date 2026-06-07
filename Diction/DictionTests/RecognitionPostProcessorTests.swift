import Testing
@testable import Diction

@Suite("Recognition post-processor")
struct RecognitionPostProcessorTests {
  private func word(_ best: String, _ alts: [String]) -> RecognizedUtterance.Word {
    RecognizedUtterance.Word(best: best, alternatives: alts)
  }

  @Test("recovery swaps an unknown best word for a known alternative")
  func recovers() {
    let utterance = RecognizedUtterance(words: [
      word("open", ["open"]),
      word("POF", ["POF", "PEOF"])
    ])
    let processor = RecognitionPostProcessor(interventions: ASRInterventions(
      vocabulary: ["PEOF"], alternativesRecovery: true, corrections: []))
    #expect(processor.process(utterance, knownWords: ["open", "peof"]) == "open PEOF")
  }

  @Test("recovery off leaves the best word in place")
  func recoveryOff() {
    let utterance = RecognizedUtterance(words: [word("POF", ["POF", "PEOF"])])
    let processor = RecognitionPostProcessor(interventions: ASRInterventions(
      vocabulary: ["PEOF"], alternativesRecovery: false, corrections: []))
    #expect(processor.process(utterance, knownWords: ["peof"]) == "POF")
  }

  @Test("a correction forces the rewrite when no alternative was offered")
  func corrects() {
    let utterance = RecognizedUtterance(words: [word("open", ["open"]), word("POF", ["POF"])])
    let processor = RecognitionPostProcessor(interventions: ASRInterventions(
      vocabulary: ["PEOF"], alternativesRecovery: true,
      corrections: [Correction(from: "POF", into: "PEOF")]))
    #expect(processor.process(utterance, knownWords: ["open", "peof"]) == "open PEOF")
  }

  @Test("a known best word is left alone even with alternatives present")
  func leavesKnown() {
    let utterance = RecognizedUtterance(words: [
      word("open", ["open"]),
      word("mailbox", ["mailbox", "mail box"])
    ])
    let processor = RecognitionPostProcessor(interventions: ASRInterventions(
      vocabulary: [], alternativesRecovery: true, corrections: []))
    #expect(processor.process(utterance, knownWords: ["open", "mailbox"]) == "open mailbox")
  }
}

@Suite("Correction apply")
struct CorrectionApplyTests {
  @Test("wholeWord replaces case-insensitively, leaving substrings alone")
  func wholeWord() {
    let correction = Correction(from: "POF", into: "PEOF", mode: .wholeWord)
    #expect(correction.apply(to: "type pof now") == "type PEOF now")
    #expect(correction.apply(to: "POFFER") == "POFFER")   // not a whole word
  }

  @Test("regex mode supports patterns and backreferences")
  func regexMode() {
    let correction = Correction(from: #"(?i)\bplugh\b"#, into: "PLUGH", mode: .regex)
    #expect(correction.apply(to: "say plugh") == "say PLUGH")
  }
}
