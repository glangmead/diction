import Testing
import Foundation
@testable import Diction

struct DemoPolicyTests {
  private func story(_ source: StoryFile.Source) -> StoryFile {
    StoryFile(
      url: URL(filePath: "/tmp/x.z5"),
      title: "X",
      format: .zMachine,
      source: source,
      lastPlayed: nil
    )
  }

  @Test("Demo plays only bundled games")
  func playabilityDemo() {
    #expect(DemoPolicy.isPlayable(story(.bundled), fullVersion: false))
    #expect(!DemoPolicy.isPlayable(story(.imported), fullVersion: false))
    #expect(!DemoPolicy.isPlayable(story(.downloaded), fullVersion: false))
  }

  @Test("Full plays every source")
  func playabilityFull() {
    for source in [StoryFile.Source.bundled, .imported, .downloaded] {
      #expect(DemoPolicy.isPlayable(story(source), fullVersion: true))
    }
  }

  @Test("The four free Kokoro voices are unlocked in demo")
  func freeVoices() {
    for id in ["af_heart", "am_michael", "bf_emma", "bm_george"] {
      #expect(DemoPolicy.isKokoroVoiceUnlocked(id, fullVersion: false))
    }
  }

  @Test("Other Kokoro voices are locked in demo, unlocked when full")
  func lockedVoices() {
    #expect(!DemoPolicy.isKokoroVoiceUnlocked("am_onyx", fullVersion: false))
    #expect(!DemoPolicy.isKokoroVoiceUnlocked("bf_alice", fullVersion: false))
    #expect(DemoPolicy.isKokoroVoiceUnlocked("am_onyx", fullVersion: true))
  }

  @Test("Effective voice falls back per role when locked in demo")
  func effectiveVoice() {
    #expect(DemoPolicy.effectiveKokoroVoice("am_onyx", role: .game, fullVersion: false) == "af_heart")
    #expect(DemoPolicy.effectiveKokoroVoice("am_onyx", role: .echo, fullVersion: false) == "am_michael")
    #expect(DemoPolicy.effectiveKokoroVoice("bf_emma", role: .game, fullVersion: false) == "bf_emma")
    #expect(DemoPolicy.effectiveKokoroVoice("am_onyx", role: .echo, fullVersion: true) == "am_onyx")
  }
}
