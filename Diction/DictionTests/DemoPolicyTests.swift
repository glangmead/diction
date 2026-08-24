import Testing
@testable import Diction

/// The free-vs-unlocked rules gate the two voice features only; games and
/// accessibility-voice narration are free. Voice commands have one exception:
/// they are free to try in a bundled game (ADR 0001). See `DemoPolicy`.
struct DemoPolicyTests {
  @Test("Neural voice is locked in demo, unlocked when full")
  func neuralVoiceGate() {
    #expect(!DemoPolicy.neuralVoiceUnlocked(fullVersion: false))
    #expect(DemoPolicy.neuralVoiceUnlocked(fullVersion: true))
  }

  /// One row of the voice-command gate matrix.
  struct VoiceCommandCase: Sendable {
    let fullVersion: Bool
    let source: StoryFile.Source
    let allowed: Bool
  }

  @Test(
    "Voice commands are allowed when unlocked, or free in a bundled game",
    arguments: [
      VoiceCommandCase(fullVersion: false, source: .bundled, allowed: true),
      VoiceCommandCase(fullVersion: false, source: .imported, allowed: false),
      VoiceCommandCase(fullVersion: false, source: .downloaded, allowed: false),
      VoiceCommandCase(fullVersion: true, source: .bundled, allowed: true),
      VoiceCommandCase(fullVersion: true, source: .imported, allowed: true),
      VoiceCommandCase(fullVersion: true, source: .downloaded, allowed: true)
    ]
  )
  func voiceCommandsGate(_ row: VoiceCommandCase) {
    #expect(
      DemoPolicy.voiceCommandsAllowed(fullVersion: row.fullVersion, source: row.source) == row.allowed
    )
  }

  @Test("Neural narration runs only when the setting is on AND unlocked")
  func usesNeuralVoiceTruthTable() {
    #expect(!DemoPolicy.usesNeuralVoice(setting: false, fullVersion: false))
    #expect(!DemoPolicy.usesNeuralVoice(setting: true, fullVersion: false))
    #expect(!DemoPolicy.usesNeuralVoice(setting: false, fullVersion: true))
    #expect(DemoPolicy.usesNeuralVoice(setting: true, fullVersion: true))
  }
}
