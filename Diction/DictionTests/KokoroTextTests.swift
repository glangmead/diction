import Testing
import Foundation
@testable import Diction

// `KokoroText.sentences` segments narration into synthesis-sized chunks. The old
// per-character "." split fragmented decimals ("3.14" → "3." + "14") and
// abbreviations ("Mr." → its own chunk), and emitted lone-period chunks from
// ellipses ("Well..." → "Well.", ".", ".") that the model voiced as a stray
// syllable at sentence boundaries. These tests pin the corrected behavior.

@Test("Splits ordinary sentences on terminal punctuation")
func splitsOrdinarySentences() {
  let out = KokoroText.sentences("Hello there. How are you?")
  #expect(out.count == 2)
  #expect(out[0].contains("Hello there"))
  #expect(out[1].contains("How are you"))
}

@Test("Keeps decimals intact instead of splitting at the point")
func keepsDecimalsIntact() {
  let out = KokoroText.sentences("It costs 3.14 dollars today.")
  #expect(out.contains { $0.contains("3.14") })
  #expect(out.allSatisfy { $0 != "3." })
}

@Test("Keeps abbreviations intact instead of splitting at the period")
func keepsAbbreviationsIntact() {
  let out = KokoroText.sentences("Mr. Smith went home. He waved.")
  #expect(out.allSatisfy { $0 != "Mr." })
  #expect(out.contains { $0.contains("Mr. Smith went home") })
}

@Test("Ellipses never produce a lone-period chunk")
func ellipsisNeverProducesLonePeriod() {
  let out = KokoroText.sentences("Well... I suppose so.")
  #expect(!out.isEmpty)
  #expect(out.allSatisfy { chunk in chunk.contains { $0.isLetter || $0.isNumber } })
}

@Test("Punctuation-only input yields no chunks to synthesize")
func punctuationOnlyYieldsNothing() {
  #expect(KokoroText.sentences("...").isEmpty)
  #expect(KokoroText.sentences("  ").isEmpty)
  #expect(KokoroText.sentences("").isEmpty)
}

@Test("Every emitted chunk has spoken content (no bare punctuation)")
func noDegenerateChunks() {
  let prose = "Hold on... Mr. Vance arrived at 4.30 p.m.! Did he? Yes."
  let out = KokoroText.sentences(prose)
  #expect(!out.isEmpty)
  #expect(out.allSatisfy { chunk in chunk.contains { $0.isLetter || $0.isNumber } })
}

@Test("A quoted question with a dialogue tag stays one sentence")
func quotedQuestionWithDialogueTagStaysOneSentence() {
  let out = KokoroText.sentences("\"City of Doors?\" you shout, leaping through.")
  #expect(out.count == 1)
  #expect(out[0].contains("City of Doors?"))
  #expect(out[0].contains("you shout"))
}

@Test("A quoted exclamation with a dialogue tag stays one sentence")
func quotedExclamationWithDialogueTagStaysOneSentence() {
  let out = KokoroText.sentences("\"Get out!\" he yelled, and ran.")
  #expect(out.count == 1)
  #expect(out[0].contains("he yelled"))
}

@Test("Genuine sentence boundaries still split (no over-merging)")
func genuineBoundariesStillSplit() {
  let out = KokoroText.sentences("He left! She stayed. Did you?")
  #expect(out.count == 3)
}

@Test("Long sentences hard-wrap under the phoneme cap")
func longSentencesWrap() {
  let long = String(repeating: "word ", count: 200).trimmingCharacters(in: .whitespaces) + "."
  let out = KokoroText.sentences(long, maxChars: 240)
  #expect(out.count > 1)
  #expect(out.allSatisfy { $0.count <= 240 })
}
