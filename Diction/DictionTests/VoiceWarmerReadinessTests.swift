import Testing
@testable import Diction

struct VoiceWarmerReadinessTests {
  @Test("Neural off → systemVoice regardless of engine state")
  func neuralOff() {
    #expect(VoiceWarmer.resolveReadiness(useKokoro: false, state: .idle) == .systemVoice)
    #expect(VoiceWarmer.resolveReadiness(useKokoro: false, state: .ready) == .systemVoice)
    #expect(VoiceWarmer.resolveReadiness(useKokoro: false, state: .unavailable("x")) == .systemVoice)
  }

  @Test("Neural on maps engine state through")
  func neuralOn() {
    #expect(VoiceWarmer.resolveReadiness(useKokoro: true, state: .idle) == .preparing)
    #expect(VoiceWarmer.resolveReadiness(useKokoro: true, state: .preparing) == .preparing)
    #expect(VoiceWarmer.resolveReadiness(useKokoro: true, state: .ready) == .ready)
    #expect(VoiceWarmer.resolveReadiness(useKokoro: true, state: .unavailable("nope")) == .unavailable("nope"))
  }
}
