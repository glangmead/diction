import Testing
@testable import Diction

/// The free-vs-unlocked rules now gate the two voice features only; games and
/// system-voice narration are free. See `DemoPolicy`.
struct DemoPolicyTests {
  @Test("Neural voice is locked in demo, unlocked when full")
  func neuralVoiceGate() {
    #expect(!DemoPolicy.neuralVoiceUnlocked(fullVersion: false))
    #expect(DemoPolicy.neuralVoiceUnlocked(fullVersion: true))
  }

  @Test("Voice input is locked in demo, unlocked when full")
  func voiceInputGate() {
    #expect(!DemoPolicy.voiceInputUnlocked(fullVersion: false))
    #expect(DemoPolicy.voiceInputUnlocked(fullVersion: true))
  }

  @Test("Neural narration runs only when the setting is on AND unlocked")
  func usesNeuralVoiceTruthTable() {
    #expect(!DemoPolicy.usesNeuralVoice(setting: false, fullVersion: false))
    #expect(!DemoPolicy.usesNeuralVoice(setting: true, fullVersion: false))
    #expect(!DemoPolicy.usesNeuralVoice(setting: false, fullVersion: true))
    #expect(DemoPolicy.usesNeuralVoice(setting: true, fullVersion: true))
  }
}
