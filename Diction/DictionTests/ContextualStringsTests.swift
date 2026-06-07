import Foundation
import Testing
@testable import Diction

@MainActor
@Suite("Contextual strings")
struct ContextualStringsTests {
  @Test("the current wake word is biased first")
  func wakeWordBiasedFirst() {
    UserDefaults.standard.set("computer", forKey: "wakeWord")
    defer { UserDefaults.standard.removeObject(forKey: "wakeWord") }
    let coordinator = VoiceCoordinator()
    let strings = coordinator.contextualStringsForTesting()
    #expect(strings.first == "computer")
  }

  @Test("profile ASR vocabulary is biased right after the wake word, before canonical terms")
  func vocabularyBiasedEarly() {
    UserDefaults.standard.removeObject(forKey: "wakeWord")   // default "game"
    let coordinator = VoiceCoordinator()
    coordinator.useSpeechProfile(SpeechProfile(asr: ASRInterventions(
      vocabulary: ["PEOF", "XYZZY"], alternativesRecovery: nil, corrections: [])))
    let strings = coordinator.contextualStringsForTesting()
    #expect(strings.first == "game")
    #expect(Array(strings.dropFirst().prefix(2)) == ["PEOF", "XYZZY"])
  }
}
