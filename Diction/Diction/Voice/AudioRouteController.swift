import AVFoundation
import Observation

/// Owns the user-controllable audio routing: which microphone input to use and a
/// live readout of the output route, plus the single source of truth for the
/// listening session's category options. Created and owned by `VoiceCoordinator`;
/// the in-game audio-routing popover binds to it, and `SpeechRecognizer` applies
/// the `ListeningSessionConfig` it produces.
///
/// It observes `routeChangeNotification` so the picker stays current and a device
/// change (e.g. AirPods removed mid-game) re-derives the config — `onConfigChange`
/// lets the coordinator restart the recognizer when the effective config moves.
@Observable
@MainActor
final class AudioRouteController {
  /// The user's input-source selection. Persisted, and resolved against what's
  /// actually available so a vanished device falls back to `.automatic`.
  private(set) var choice: AudioInputChoice = .automatic

  /// Inputs the system currently offers, for the popover's picker.
  private(set) var availableInputs: [AudioInputOption] = []

  /// Human-readable name of the current output port, shown under the route button.
  private(set) var currentOutputName = ""

  /// Invoked (on the main actor) when the user picks a new input or a hardware
  /// route change alters availability. The coordinator uses it to reconfigure a
  /// live recognizer.
  @ObservationIgnored var onConfigChange: (@MainActor () -> Void)?

  @ObservationIgnored private let defaults: UserDefaults
  /// `nonisolated(unsafe)`: the token is set once in `init` and read only in
  /// `deinit`, which Swift 6 treats as nonisolated and so can't touch a
  /// non-Sendable main-actor property. (`isolated deinit` needs iOS 18.4.)
  @ObservationIgnored nonisolated(unsafe) private var routeObserver: NSObjectProtocol?

  private static let choiceTypeKey = "audioInputChoiceType"
  private static let choiceUIDKey = "audioInputChoiceUID"
  private static let automaticToken = "automatic"

  private static let bluetoothPorts: Set<AVAudioSession.Port> =
    [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    loadChoice()
    refresh()
    routeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: nil
    ) { [weak self] note in
      // The notification arrives on an arbitrary queue. Unwrap here (a plain load)
      // so the main-actor hop captures a local constant rather than `init`'s still-
      // mutable `self` — the latter is a Swift 6 concurrent-capture error. The reason
      // raw value (Sendable) is extracted here for the same reason.
      guard let self else { return }
      let reasonRaw = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
      Task { @MainActor in
        self.refresh()
        self.logRouteChange(reasonRaw: reasonRaw)
        self.onConfigChange?()
      }
    }
  }

  deinit {
    if let routeObserver {
      NotificationCenter.default.removeObserver(routeObserver)
    }
  }

  // MARK: - Selection

  /// Apply a new input choice: persist it and notify so a live recognizer can
  /// reconfigure. No-op if unchanged.
  func select(_ newChoice: AudioInputChoice) {
    guard newChoice != choice else { return }
    choice = newChoice
    persistChoice()
    onConfigChange?()
  }

  // MARK: - Config

  /// The session config for the current choice and live output route.
  func currentConfig() -> ListeningSessionConfig {
    ListeningSessionConfig.make(
      choice: choice,
      output: currentOutputContext(),
      preferredInputUID: resolvedPreferredInputUID())
  }

  // MARK: - Route inspection

  /// Re-read the available inputs and current output, and drop a selection whose
  /// device has disappeared.
  func refresh() {
    let session = AVAudioSession.sharedInstance()
    availableInputs = (session.availableInputs ?? []).map {
      AudioInputOption(id: $0.uid, name: $0.portName, portType: $0.portType)
    }
    currentOutputName = session.currentRoute.outputs.first?.portName ?? ""
    if case .port(let uid, _) = choice,
       !availableInputs.contains(where: { $0.id == uid }) {
      choice = .automatic
      persistChoice()
    }
  }

  private func currentOutputContext() -> OutputContext {
    let session = AVAudioSession.sharedInstance()
    let outputs = session.currentRoute.outputs
    if outputs.contains(where: { Self.bluetoothPorts.contains($0.portType) }) {
      return .bluetooth
    }
    // A connected Bluetooth device shows up as an available HFP input even when the
    // current output is still the speaker (we configure the route afterwards).
    if (session.availableInputs ?? []).contains(where: { $0.portType == .bluetoothHFP }) {
      return .bluetooth
    }
    if outputs.contains(where: { $0.portType == .headphones }) {
      return .wired
    }
    return .builtInOnly
  }

  private func resolvedPreferredInputUID() -> String? {
    guard case .port(let uid, _) = choice,
          availableInputs.contains(where: { $0.id == uid }) else { return nil }
    return uid
  }

  // MARK: - Diagnostics

  /// Temporary probe: log every route change with its reason and the resolved
  /// output context, to confirm whether route changes fire during narration.
  private func logRouteChange(reasonRaw: UInt) {
    let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) ?? .unknown
    DiagnosticsLog.routeChange(
      reason: Self.describe(reason),
      output: Self.describe(currentOutputContext()))
  }

  private static func describe(_ reason: AVAudioSession.RouteChangeReason) -> String {
    switch reason {
    case .unknown: return "unknown"
    case .newDeviceAvailable: return "newDevice"
    case .oldDeviceUnavailable: return "oldDeviceGone"
    case .categoryChange: return "categoryChange"
    case .override: return "override"
    case .wakeFromSleep: return "wake"
    case .noSuitableRouteForCategory: return "noRoute"
    case .routeConfigurationChange: return "configChange"
    @unknown default: return "other(\(reason.rawValue))"
    }
  }

  private static func describe(_ output: OutputContext) -> String {
    switch output {
    case .builtInOnly: return "builtInOnly"
    case .wired: return "wired"
    case .bluetooth: return "bluetooth"
    }
  }

  // MARK: - Persistence

  private func loadChoice() {
    guard let type = defaults.string(forKey: Self.choiceTypeKey),
          type != Self.automaticToken else {
      choice = .automatic
      return
    }
    let uid = defaults.string(forKey: Self.choiceUIDKey) ?? ""
    choice = .port(uid: uid, portType: AVAudioSession.Port(rawValue: type))
  }

  private func persistChoice() {
    switch choice {
    case .automatic:
      defaults.set(Self.automaticToken, forKey: Self.choiceTypeKey)
      defaults.removeObject(forKey: Self.choiceUIDKey)
    case .port(let uid, let portType):
      defaults.set(portType.rawValue, forKey: Self.choiceTypeKey)
      defaults.set(uid, forKey: Self.choiceUIDKey)
    }
  }
}
