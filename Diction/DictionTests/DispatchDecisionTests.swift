import Testing
@testable import Diction

@MainActor
@Suite("Dispatch decision")
struct DispatchDecisionTests {
  @Test("bare utterance goes to the game when idle")
  func bareIdle() {
    #expect(VoiceCoordinator.decide(text: "take lamp", wakeWord: "game", isNarrating: false) == .game)
  }

  @Test("bare utterance is dropped while narrating")
  func bareNarrating() {
    #expect(VoiceCoordinator.decide(text: "take lamp", wakeWord: "game", isNarrating: true) == .ignore)
  }

  @Test("wake-word stop interrupts even while narrating")
  func wakeStopNarrating() {
    #expect(VoiceCoordinator.decide(text: "game stop", wakeWord: "game", isNarrating: true) == .coordinator(.stop))
  }

  @Test("addressed but unparsed is ignored")
  func addressedNoMatch() {
    #expect(VoiceCoordinator.decide(text: "game flibbertigibbet", wakeWord: "game", isNarrating: false) == .ignore)
  }

  @Test("bare wake word with no command is ignored")
  func bareWakeWord() {
    #expect(VoiceCoordinator.decide(text: "game", wakeWord: "game", isNarrating: false) == .ignore)
  }

  @Test("merged wake word + command (recognizer ran them together) is honored")
  func mergedWakeCommand() {
    #expect(VoiceCoordinator.decide(text: "GameStop", wakeWord: "game", isNarrating: true) == .coordinator(.stop))
  }

  @Test("a real word that merely starts with the wake word still reaches the game")
  func wakePrefixNotACommand() {
    #expect(VoiceCoordinator.decide(text: "gamekeeper", wakeWord: "game", isNarrating: false) == .game)
  }

  @Test("matching is case-insensitive and tolerates punctuation")
  func caseAndPunctuation() {
    #expect(
      VoiceCoordinator.decide(text: "Game, reread", wakeWord: "game", isNarrating: false) == .coordinator(.reread)
    )
  }

  @Test("custom wake word is honored")
  func customWake() {
    #expect(
      VoiceCoordinator.decide(text: "computer faster", wakeWord: "computer", isNarrating: false)
        == .coordinator(.faster)
    )
  }

  @Test("a numbered readback command routes through the wake word")
  func numberedThroughWake() {
    #expect(
      VoiceCoordinator.decide(text: "game window 2", wakeWord: "game", isNarrating: false)
        == .coordinator(.window(2))
    )
  }

  @Test("merged wake word + numbered command is honored")
  func mergedNumbered() {
    #expect(
      VoiceCoordinator.decide(text: "gamewindow2", wakeWord: "game", isNarrating: false)
        == .coordinator(.window(2))
    )
  }
}

@MainActor
@Suite("Character from utterance")
struct CharacterFromUtteranceTests {
  @Test("spoken digit words and bare digits map to digit characters")
  func digits() {
    #expect(VoiceCoordinator.characterFromUtterance("zero") == "0")
    #expect(VoiceCoordinator.characterFromUtterance("five") == "5")
    #expect(VoiceCoordinator.characterFromUtterance("nine") == "9")
    #expect(VoiceCoordinator.characterFromUtterance("0") == "0")
  }

  @Test("control words still map")
  func controlWords() {
    #expect(VoiceCoordinator.characterFromUtterance("space") == " ")
    #expect(VoiceCoordinator.characterFromUtterance("yes") == "y")
    #expect(VoiceCoordinator.characterFromUtterance("no") == "n")
  }
}

@MainActor
@Suite("Wake-word normalization")
struct WakeWordTests {
  @Test("nil falls back to game") func nilFallback() {
    #expect(VoiceCoordinator.normalizedWakeWord(nil) == "game")
  }
  @Test("empty falls back to game") func emptyFallback() {
    #expect(VoiceCoordinator.normalizedWakeWord("   ") == "game")
  }
  @Test("trims and lowercases") func trimLower() {
    #expect(VoiceCoordinator.normalizedWakeWord("  GAME ") == "game")
  }
}
