import Testing
@testable import Diction

@Suite("Recognition restart policy")
struct RecognitionRestartPolicyTests {
  @Test("a quick, empty cycle is a fast failure (the thrash signature)")
  func fastEmptyCycleIsFailure() {
    #expect(RecognitionRestartPolicy.isFastFailure(producedText: false, duration: .milliseconds(0)) == true)
    #expect(RecognitionRestartPolicy.isFastFailure(producedText: false, duration: .milliseconds(50)) == true)
    #expect(RecognitionRestartPolicy.isFastFailure(producedText: false, duration: .milliseconds(299)) == true)
  }

  @Test("a cycle that produced any text is never a fast failure")
  func productiveCycleIsNotFailure() {
    #expect(RecognitionRestartPolicy.isFastFailure(producedText: true, duration: .milliseconds(5)) == false)
  }

  @Test("a cycle that ran a healthy duration is not a fast failure even if empty")
  func slowEmptyCycleIsNotFailure() {
    #expect(RecognitionRestartPolicy.isFastFailure(producedText: false, duration: .milliseconds(300)) == false)
    #expect(RecognitionRestartPolicy.isFastFailure(producedText: false, duration: .seconds(3)) == false)
  }

  @Test("healthy listening re-arms immediately (no added latency)")
  func zeroFailuresRestartImmediately() {
    #expect(RecognitionRestartPolicy.restartDelay(consecutiveFastFailures: 0) == .zero)
  }

  @Test("consecutive fast failures back off exponentially")
  func backoffGrows() {
    #expect(RecognitionRestartPolicy.restartDelay(consecutiveFastFailures: 1) == .milliseconds(100))
    #expect(RecognitionRestartPolicy.restartDelay(consecutiveFastFailures: 2) == .milliseconds(200))
    #expect(RecognitionRestartPolicy.restartDelay(consecutiveFastFailures: 3) == .milliseconds(400))
    #expect(RecognitionRestartPolicy.restartDelay(consecutiveFastFailures: 4) == .milliseconds(800))
  }

  @Test("backoff is capped so a permanently-failing recognizer idles, not spins")
  func backoffCapped() {
    #expect(RecognitionRestartPolicy.restartDelay(consecutiveFastFailures: 6) == .seconds(2))
    #expect(RecognitionRestartPolicy.restartDelay(consecutiveFastFailures: 1000) == .seconds(2))
  }
}
