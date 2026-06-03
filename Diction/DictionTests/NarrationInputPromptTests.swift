import Testing
@testable import Diction

@Suite("Narration input prompt")
struct NarrationInputPromptTests {
  @Test("visible only while narrating and the field is unfocused")
  func visibility() {
    #expect(NarrationInputPrompt.isVisible(isNarrating: true, isFieldFocused: false) == true)
    #expect(NarrationInputPrompt.isVisible(isNarrating: true, isFieldFocused: true) == false)
    #expect(NarrationInputPrompt.isVisible(isNarrating: false, isFieldFocused: false) == false)
    #expect(NarrationInputPrompt.isVisible(isNarrating: false, isFieldFocused: true) == false)
  }

  @Test("message is shown while narrating")
  func message() {
    #expect(NarrationInputPrompt.message(wakeWord: "game") == "(Narrating)")
  }
}
