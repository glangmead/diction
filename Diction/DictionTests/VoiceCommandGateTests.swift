import Testing
@testable import Diction

/// `VoiceCoordinator.setListening(true)` is the one choke point for the voice
/// command gate: the Settings toggle is live for every user, so a free user can
/// flip it on from inside a locked game and the coordinator must refuse.
@MainActor
@Suite("Voice command gate")
struct VoiceCommandGateTests {
  @Test("the gate is closed until a game installs one")
  func closedByDefault() async {
    let coordinator = VoiceCoordinator()
    await coordinator.setListening(true)
    #expect(!coordinator.isListening)
  }

  @Test("setListening(true) is refused while the gate says no")
  func refusedWhenGateDenies() async {
    let coordinator = VoiceCoordinator()
    coordinator.useVoiceCommandGate { false }
    await coordinator.setListening(true)
    #expect(!coordinator.isListening)
  }
}
