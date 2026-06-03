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

  @Test("message names the default wake word and how to interrupt")
  func defaultMessage() {
    #expect(NarrationInputPrompt.message(wakeWord: "game") == "(Narrating. Say “game stop” to interrupt.)")
  }

  @Test("message honors a custom wake word")
  func customMessage() {
    #expect(NarrationInputPrompt.message(wakeWord: "computer") == "(Narrating. Say “computer stop” to interrupt.)")
  }
}
