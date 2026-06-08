import Foundation

/// Decides whether a finished capture cycle should deliver its transcription to
/// the parser.
///
/// A continuous-mode cycle ends one of two ways: on a final result (Apple's own
/// endpoint), or on an error. On-device recognition routinely ends a cycle with
/// a transient error (`kAFAssistantErrorDomain` 1101 / 203 …) *in place of* the
/// final result — most often right after `endAudio()` fires on our 1.2 s silence
/// endpoint. The cycle has nonetheless captured a complete utterance: the
/// transcription went stable for the whole silence window and was already echoed
/// live in the input bar. Tearing the cycle down without delivering it loses the
/// command silently — the user sees their words appear, then vanish unexecuted.
///
/// So the rule: deliver whenever there is text AND the cycle either reached a
/// final result or the user had endpointed it (silence-triggered `endAudio`). An
/// error that arrives *before* any endpoint is a genuine mid-stream failure whose
/// text may be a half-spoken partial — delivering it would truncate the command,
/// so it is dropped.
enum RecognitionFinalizationPolicy {
  static func shouldDeliver(isFinal: Bool, endpointed: Bool, hasText: Bool) -> Bool {
    hasText && (isFinal || endpointed)
  }
}
