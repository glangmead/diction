import Testing
@testable import Diction

@Suite("Recognition finalization policy")
struct RecognitionFinalizationPolicyTests {
  @Test("a final result carrying text is delivered")
  func finalWithText() {
    #expect(RecognitionFinalizationPolicy.shouldDeliver(
      isFinal: true, endpointed: false, hasText: true))
  }

  @Test("an errored cycle is delivered once the user endpointed it")
  func errorAfterEndpoint() {
    // The on-device task often errors in place of the final result right after
    // the silence endpoint fires endAudio; the utterance is complete and stable,
    // so it must still reach the parser rather than vanish.
    #expect(RecognitionFinalizationPolicy.shouldDeliver(
      isFinal: false, endpointed: true, hasText: true))
  }

  @Test("a mid-stream error that never endpointed is dropped")
  func errorMidStream() {
    // No silence endpoint yet: the text may be a half-spoken partial, so dropping
    // it is correct — delivering would truncate the command.
    #expect(!RecognitionFinalizationPolicy.shouldDeliver(
      isFinal: false, endpointed: false, hasText: true))
  }

  @Test("an empty cycle is never delivered")
  func emptyNeverDelivered() {
    #expect(!RecognitionFinalizationPolicy.shouldDeliver(
      isFinal: true, endpointed: true, hasText: false))
    #expect(!RecognitionFinalizationPolicy.shouldDeliver(
      isFinal: false, endpointed: true, hasText: false))
  }
}
