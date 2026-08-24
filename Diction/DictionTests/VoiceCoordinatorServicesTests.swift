import Testing
@testable import Diction

/// `VoiceCoordinator` builds its services on first use rather than in `init`
/// (impl ticket 03). These pin what must survive that: each service is one
/// stable instance, and the route controller's callback is still installed.
/// (The synthesizer's `isRecognizerLive` closure has a `{ false }` default, so
/// its wiring isn't observable from here.)
@MainActor
@Suite("Voice coordinator services")
struct VoiceCoordinatorServicesTests {
  @Test("each service is a single stable instance")
  func servicesAreStable() {
    let coordinator = VoiceCoordinator()
    #expect(coordinator.recognizer === coordinator.recognizer)
    #expect(coordinator.synthesizer === coordinator.synthesizer)
    #expect(coordinator.audioRoute === coordinator.audioRoute)
  }

  @Test("the route controller reports config changes to the coordinator")
  func routeControllerIsWired() {
    let coordinator = VoiceCoordinator()
    #expect(coordinator.audioRoute.onConfigChange != nil)
  }
}
