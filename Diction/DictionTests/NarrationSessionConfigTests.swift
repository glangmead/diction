import AVFoundation
import Testing
@testable import Diction

@Suite("Narration session policy")
struct NarrationSessionConfigTests {
  @Test("narration with no recognizer runs under a plain playback session that ducks other audio")
  func standardIsPlayback() {
    let config = NarrationSessionConfig.standard
    #expect(config.category == .playback)
    #expect(config.mode == .default)
    #expect(config.options == [.duckOthers])
  }

  @Test("a narrator configures the session when no recognizer is live and it isn't already playback")
  func appliesWhenRecognizerNotLive() {
    #expect(NarrationSessionConfig.shouldApply(recognizerLive: false, currentCategory: .playAndRecord))
    #expect(NarrationSessionConfig.shouldApply(recognizerLive: false, currentCategory: .soloAmbient))
    #expect(NarrationSessionConfig.shouldApply(recognizerLive: false, currentCategory: .ambient))
  }

  @Test("a session already in playback is left alone")
  func skipsWhenAlreadyPlayback() {
    #expect(!NarrationSessionConfig.shouldApply(recognizerLive: false, currentCategory: .playback))
  }

  @Test("a live recognizer owns the session; the narrator never touches it, whatever the category")
  func leavesLiveRecognizerAlone() {
    #expect(!NarrationSessionConfig.shouldApply(recognizerLive: true, currentCategory: .playAndRecord))
    #expect(!NarrationSessionConfig.shouldApply(recognizerLive: true, currentCategory: .playback))
    #expect(!NarrationSessionConfig.shouldApply(recognizerLive: true, currentCategory: .soloAmbient))
  }
}
