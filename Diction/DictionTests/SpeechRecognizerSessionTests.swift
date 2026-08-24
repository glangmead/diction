import AVFoundation
import Testing
@testable import Diction

/// Records the session calls the recognizer makes, so the stop path can be
/// asserted without audio hardware.
@MainActor
private final class FakeAudioSession: AudioSessionControlling {
  struct CategoryCall: Equatable {
    var category: AVAudioSession.Category
    var mode: AVAudioSession.Mode
    var options: AVAudioSession.CategoryOptions
  }

  var availableInputs: [AVAudioSessionPortDescription]?
  private(set) var categoryCalls: [CategoryCall] = []
  private(set) var activeCalls: [Bool] = []

  func setCategory(
    _ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions
  ) throws {
    categoryCalls.append(CategoryCall(category: category, mode: mode, options: options))
  }

  func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
    activeCalls.append(active)
  }

  func setPreferredInput(_ inPort: AVAudioSessionPortDescription?) throws {}
}

@Suite("Recognizer audio-session handover")
@MainActor
struct SpeechRecognizerSessionTests {
  @Test("stopping listening hands the session back as playback without deactivating it")
  func stopRestoresPlaybackWithoutDeactivating() {
    let session = FakeAudioSession()
    let recognizer = SpeechRecognizer(session: session)

    recognizer.stopContinuous()

    // Deactivating here wedged neural narration and left accessibility-voice
    // narration near-mute (impl #02).
    #expect(!session.activeCalls.contains(false))
    #expect(session.categoryCalls.last
      == FakeAudioSession.CategoryCall(category: .playback, mode: .default, options: [.duckOthers]))
  }
}
