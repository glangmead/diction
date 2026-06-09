/// The output situation at the moment listening starts — what the routing policy
/// needs to decide whether to force the speaker and whether Bluetooth options
/// apply. Resolved from the live route by `AudioRouteController`.
enum OutputContext: Equatable {
  /// No headphones or Bluetooth — narration should use the loud built-in speaker
  /// rather than the quiet receiver.
  case builtInOnly
  /// Wired headphones, which carry their own route for both directions.
  case wired
  /// A Bluetooth audio device (e.g. AirPods) is connected.
  case bluetooth
}
