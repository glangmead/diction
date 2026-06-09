import AVFoundation

/// The user's microphone-source selection, surfaced in the in-game audio-routing
/// popover and persisted across launches by `AudioRouteController`.
///
/// `.automatic` lets the system pick the input from the active route (the prior,
/// only behaviour). `.port` pins a specific input by its stable UID; the
/// `portType` rides along so the routing policy can recognise the built-in mic
/// without a live `AVAudioSession` lookup — see
/// `ListeningSessionConfig.make(choice:output:preferredInputUID:)`.
enum AudioInputChoice: Hashable {
  case automatic
  case port(uid: String, portType: AVAudioSession.Port)
}
