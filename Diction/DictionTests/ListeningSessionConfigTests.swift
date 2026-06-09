import AVFoundation
import Testing
@testable import Diction

@Suite("Listening session routing policy")
struct ListeningSessionConfigTests {
  @Test("no headphones forces the loud speaker, mic built-in, VPIO on")
  func builtInOnly() {
    let config = ListeningSessionConfig.make(
      choice: .automatic, output: .builtInOnly, preferredInputUID: nil)
    #expect(config.options == [.duckOthers, .defaultToSpeaker])
    #expect(config.enableVoiceProcessing == true)
    #expect(config.preferredInputUID == nil)
  }

  @Test("wired headphones keep their own route — no speaker override")
  func wired() {
    let config = ListeningSessionConfig.make(
      choice: .automatic, output: .wired, preferredInputUID: nil)
    #expect(config.options == [.duckOthers])
    #expect(!config.options.contains(.defaultToSpeaker))
    #expect(config.enableVoiceProcessing == true)
  }

  @Test("bluetooth + automatic stays on the AirPods both ways (HFP + A2DP), VPIO on")
  func bluetoothAutomatic() {
    let config = ListeningSessionConfig.make(
      choice: .automatic, output: .bluetooth, preferredInputUID: nil)
    #expect(config.options.contains(.allowBluetoothHFP))
    #expect(config.options.contains(.allowBluetoothA2DP))
    #expect(!config.options.contains(.defaultToSpeaker))
    #expect(config.enableVoiceProcessing == true)
  }

  @Test("bluetooth + the bluetooth mic chosen behaves like the shared-device case")
  func bluetoothMicChosen() {
    let choice = AudioInputChoice.port(uid: "airpods-uid", portType: .bluetoothHFP)
    let config = ListeningSessionConfig.make(
      choice: choice, output: .bluetooth, preferredInputUID: "airpods-uid")
    #expect(config.options.contains(.allowBluetoothHFP))
    #expect(config.enableVoiceProcessing == true)
    #expect(config.preferredInputUID == "airpods-uid")
  }

  @Test("bluetooth + built-in mic keeps full-quality A2DP output and drops VPIO (split device)")
  func bluetoothSplitDevice() {
    let choice = AudioInputChoice.port(uid: "builtin-uid", portType: .builtInMic)
    let config = ListeningSessionConfig.make(
      choice: choice, output: .bluetooth, preferredInputUID: "builtin-uid")
    #expect(config.options.contains(.allowBluetoothA2DP))
    #expect(!config.options.contains(.allowBluetoothHFP))
    #expect(config.enableVoiceProcessing == false)
    #expect(config.preferredInputUID == "builtin-uid")
  }

  @Test("the speaker is never force-routed when any external output is present")
  func neverForcesSpeakerWithExternalOutput() {
    for output in [OutputContext.wired, .bluetooth] {
      let config = ListeningSessionConfig.make(
        choice: .automatic, output: output, preferredInputUID: nil)
      #expect(!config.options.contains(.defaultToSpeaker))
    }
  }
}
