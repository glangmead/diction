import AVFoundation

/// A selectable microphone input, shown as a row in the audio-routing popover.
/// A thin display projection of `AVAudioSessionPortDescription` so the view layer
/// never touches `AVAudioSession` directly.
struct AudioInputOption: Identifiable, Equatable {
  /// The port's stable UID — also the `AudioInputChoice.port` discriminator.
  let id: String
  let name: String
  let portType: AVAudioSession.Port
}
