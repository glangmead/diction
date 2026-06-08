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

  private func spelled(_ letters: String) -> [RecognizedUtterance.Word] {
    letters.map { word(String($0), [String($0)]) }
  }

  @Test("joins a spelled run into a known parser word")
  func joinsSpelled() {
    let utterance = RecognizedUtterance(words: spelled("WNNF"))
    let processor = RecognitionPostProcessor(interventions: ASRInterventions(
      vocabulary: [], alternativesRecovery: false, joinSpelledWords: true, corrections: []))
    #expect(processor.process(utterance, knownWords: ["wnnf"]) == "WNNF")
  }

  @Test("leaves a spelled run alone when the join isn't a known word")
  func joinUnknown() {
    let utterance = RecognizedUtterance(words: spelled("WNNF"))
    let processor = RecognitionPostProcessor(interventions: ASRInterventions(
      vocabulary: [], alternativesRecovery: false, joinSpelledWords: true, corrections: []))
    #expect(processor.process(utterance, knownWords: ["west", "north"]) == "W N N F")
  }

  @Test("join off leaves the run spelled")
  func joinOff() {
    let utterance = RecognizedUtterance(words: spelled("WNNF"))
    let processor = RecognitionPostProcessor(interventions: ASRInterventions(
      vocabulary: [], alternativesRecovery: false, joinSpelledWords: false, corrections: []))
    #expect(processor.process(utterance, knownWords: ["wnnf"]) == "W N N F")
  }

  @Test("joins a run embedded among other words")
  func joinEmbedded() {
    let utterance = RecognizedUtterance(words: [word("open", ["open"])] + spelled("WNNF"))
    let processor = RecognitionPostProcessor(interventions: ASRInterventions(
      vocabulary: [], alternativesRecovery: false, joinSpelledWords: true, corrections: []))
    #expect(processor.process(utterance, knownWords: ["open", "wnnf"]) == "open WNNF")
  }

  @Test("joins the longest known prefix, leaving the rest spelled")
  func joinLongestPrefix() {
    let utterance = RecognizedUtterance(words: spelled("WNNFG"))
    let processor = RecognitionPostProcessor(interventions: ASRInterventions(
      vocabulary: [], alternativesRecovery: false, joinSpelledWords: true, corrections: []))
    #expect(processor.process(utterance, knownWords: ["wnnf"]) == "WNNF G")
  }

  @Test("the optional log reports each word's candidates and the recovery decision")
  func logsTrace() {
    var lines: [String] = []
    let utterance = RecognizedUtterance(words: [word("open", ["open"]), word("POF", ["POF", "PEOF"])])
    let processor = RecognitionPostProcessor(interventions: ASRInterventions(
      vocabulary: ["PEOF"], alternativesRecovery: true, corrections: []))
    _ = processor.process(utterance, knownWords: ["open", "peof"], log: { lines.append($0) })
    let joined = lines.joined(separator: "\n")
    #expect(joined.contains("POF"))
    #expect(joined.contains("PEOF"))        // the recovered candidate is shown
    #expect(joined.contains("candidates"))  // the candidate list is logged
  }

  @Test("recovery leaves a multi-word segment alone instead of truncating it")
  func leavesMultiWordSegment() {
    // Apple sometimes returns a whole short command as a single segment whose
    // substring is multi-word ("Take all") with multi-word alternatives. The
    // single-word recovery test must not fire here and drop a word.
    let utterance = RecognizedUtterance(words: [word("Take all", ["Take all", "Take off", "Take"])])
    let processor = RecognitionPostProcessor(interventions: ASRInterventions(
      vocabulary: [], alternativesRecovery: true, corrections: []))
    #expect(processor.process(utterance, knownWords: ["take", "all", "off"]) == "Take all")
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
