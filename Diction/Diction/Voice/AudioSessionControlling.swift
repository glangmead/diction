import AVFoundation

/// The slice of `AVAudioSession` the recognizer drives. `AVAudioSession` conforms
/// with no glue, so production passes `sharedInstance()`; tests pass a recorder
/// and assert on the calls (see `SpeechRecognizerSessionTests`).
@MainActor
protocol AudioSessionControlling: AnyObject {
  var availableInputs: [AVAudioSessionPortDescription]? { get }
  func setCategory(
    _ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions
  ) throws
  func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
  func setPreferredInput(_ inPort: AVAudioSessionPortDescription?) throws
}

extension AVAudioSession: AudioSessionControlling {}
