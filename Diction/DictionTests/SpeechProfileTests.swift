import Testing
import Foundation
@testable import Diction

@Suite("Speech profile decode + merge")
struct SpeechProfileTests {
  private func decode(_ json: String) throws -> SpeechProfile {
    try SpeechProfile.decode(Data(json.utf8))
  }

  @Test("decodes a full profile")
  func decodesFull() throws {
    let profile = try decode(#"""
    {
      "schemaVersion": 1,
      "tts": {
        "pronunciations": [
          { "word": "copied", "ipa": "kˈɑpid" },
          { "word": "PRSO", "say": "parser object" }
        ],
        "textRules": [
          { "id": "zork-casing", "where": "before-g2p", "match": "\\bZORK\\b", "action": "replace", "with": "Zork" }
        ],
        "pausePolicy": { "comma": 1, "semicolon": 1, "colon": 1, "dash": 3 }
      },
      "asr": {
        "vocabulary": ["PEOF", "XYZZY"],
        "alternativesRecovery": true,
        "corrections": [ { "from": "POF", "to": "PEOF", "mode": "wholeWord" } ]
      }
    }
    """#)
    #expect(profile.tts.pronunciationsByWord["copied"]?.ipa == "kˈɑpid")
    #expect(profile.tts.pronunciationsByWord["prso"]?.say == "parser object")
    #expect(profile.tts.textRules.first?.action == .replace)
    #expect(profile.tts.textRules.first?.stage == "before-g2p")
    #expect(profile.tts.pausePolicy?.dash == 3)
    #expect(profile.asr.vocabulary.contains("PEOF"))
    #expect(profile.asr.alternativesRecovery == true)
    #expect(profile.asr.corrections.first?.into == "PEOF")
  }

  @Test("a partial overlay decodes with defaults for omitted keys")
  func decodesPartial() throws {
    let profile = try decode(#"{ "tts": { "pronunciations": [ { "word": "x", "ipa": "y" } ] } }"#)
    #expect(profile.tts.pronunciations.count == 1)
    #expect(profile.tts.textRules.isEmpty)
    #expect(profile.tts.pausePolicy == nil)        // absent → don't touch the base
    #expect(profile.asr == .empty)
  }

  @Test("overlay pronunciations replace by word and union new ones")
  func mergePronunciations() {
    let base = SpeechProfile(tts: TTSInterventions(
      pronunciations: [PronEntry(word: "copied", ipa: "old")], textRules: [], pausePolicy: nil))
    let overlay = SpeechProfile(tts: TTSInterventions(
      pronunciations: [PronEntry(word: "Copied", ipa: "new"), PronEntry(word: "grue", ipa: "g")],
      textRules: [], pausePolicy: nil))
    let merged = base.merging(overlay)
    #expect(merged.tts.pronunciationsByWord["copied"]?.ipa == "new")
    #expect(merged.tts.pronunciationsByWord["grue"]?.ipa == "g")
    #expect(merged.tts.pronunciationsByWord.count == 2)
  }

  @Test("overlay textRules replace by id and append new ones in order")
  func mergeTextRules() {
    let base = SpeechProfile(tts: TTSInterventions(
      pronunciations: [],
      textRules: [TextRule(id: "a", match: "x", action: .replace, with: "1")],
      pausePolicy: nil))
    let overlay = SpeechProfile(tts: TTSInterventions(
      pronunciations: [],
      textRules: [
        TextRule(id: "a", match: "x", action: .replace, with: "2"),
        TextRule(id: "b", match: "y", action: .spaceDigits)
      ],
      pausePolicy: nil))
    let merged = base.merging(overlay)
    #expect(merged.tts.textRules.map(\.id) == ["a", "b"])
    #expect(merged.tts.textRules.first?.with == "2")   // replaced in place
  }

  @Test("overlay pausePolicy wins; nil keeps the base")
  func mergePausePolicy() {
    let base = SpeechProfile(tts: TTSInterventions(pronunciations: [], textRules: [], pausePolicy: .default))
    let setOverlay = SpeechProfile(tts: TTSInterventions(
      pronunciations: [], textRules: [], pausePolicy: PausePolicy(comma: 2, semicolon: 1, colon: 1, dash: 3)))
    #expect(base.merging(setOverlay).tts.pausePolicy?.comma == 2)

    let nilOverlay = SpeechProfile(tts: .empty)
    #expect(base.merging(nilOverlay).tts.pausePolicy?.dash == 3)
  }

  @Test("overlay vocabulary + corrections union; alternativesRecovery wins when set")
  func mergeASR() {
    let base = SpeechProfile(asr: ASRInterventions(
      vocabulary: ["PEOF"], alternativesRecovery: true,
      corrections: [Correction(from: "POF", into: "PEOF")]))
    let overlay = SpeechProfile(asr: ASRInterventions(
      vocabulary: ["PEOF", "XYZZY"], alternativesRecovery: nil,
      corrections: [Correction(from: "GUF", into: "GRUE")]))
    let merged = base.merging(overlay)
    #expect(merged.asr.vocabulary == ["PEOF", "XYZZY"])           // union, deduped, order kept
    #expect(merged.asr.corrections.count == 2)
    #expect(merged.asr.alternativesRecovery == true)              // nil overlay keeps base
  }
}
