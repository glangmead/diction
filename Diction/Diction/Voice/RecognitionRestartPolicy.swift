import Foundation

/// Decides how soon the continuous recognizer should re-arm its next capture
/// cycle after the previous one ends.
///
/// Continuous mode tears down and recreates the recognition request on every
/// cycle boundary. Normally a cycle ends only after it has done real work (a
/// final result, or a silence timeout following speech), so re-arming instantly
/// keeps listening seamless. But when the recognizer errors *before it can
/// capture anything* — the on-device model still cold-loading right after the
/// audio engine starts, or a Simulator with no on-device model at all — the
/// task calls back in well under a millisecond, and an unguarded restart busy-
/// loops the request hundreds of times a second. That CPU storm also shreds the
/// user's first spoken command, since each utterance's audio is thrown away
/// before it can stabilise into a final.
///
/// This policy distinguishes a healthy cycle from that thrash by duration, and
/// backs the restart off exponentially while the thrash persists — resetting to
/// instant the moment a cycle does real work again.
enum RecognitionRestartPolicy {
  /// A cycle shorter than this that produced no text is treated as a failure to
  /// capture rather than a normal end-of-utterance. Well above any real cycle's
  /// floor (the silence timeout alone is 1.2 s) and far below normal, so benign
  /// "no speech" errors after a few seconds of silence don't count as thrash.
  static let minHealthyCycle: Duration = .milliseconds(300)

  /// First backoff step; doubles per consecutive fast failure.
  static let baseBackoff: Duration = .milliseconds(100)

  /// Ceiling on the backoff, so a permanently-failing recognizer idles at this
  /// cadence instead of spinning — while still re-arming within this bound once
  /// it recovers.
  static let maxBackoff: Duration = .seconds(2)

  /// Whether the just-ended cycle is the signature of the recognizer erroring
  /// before capturing audio: it ran briefly *and* produced no transcription.
  static func isFastFailure(producedText: Bool, duration: Duration) -> Bool {
    !producedText && duration < minHealthyCycle
  }

  /// Delay before starting the next cycle given the current run of consecutive
  /// fast failures. Zero while healthy (instant, continuous listening);
  /// exponential backoff capped at `maxBackoff` once thrashing.
  static func restartDelay(consecutiveFastFailures: Int) -> Duration {
    guard consecutiveFastFailures > 0 else { return .zero }
    let shift = min(consecutiveFastFailures - 1, 5)
    let scaled = baseBackoff * (1 << shift)
    return scaled > maxBackoff ? maxBackoff : scaled
  }
}
