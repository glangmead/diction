import Foundation
import Testing
@testable import Diction

@MainActor
@Suite("Contextual strings")
struct ContextualStringsTests {
  @Test("the current wake word is biased first")
  func wakeWordBiasedFirst() {
    UserDefaults.standard.set("computer", forKey: "wakeWord")
    defer { UserDefaults.standard.removeObject(forKey: "wakeWord") }
    let coordinator = VoiceCoordinator()
    let strings = coordinator.contextualStringsForTesting()
    #expect(strings.first == "computer")
  }
}
