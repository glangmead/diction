import Foundation
import os

/// Central `os.Logger` facility. All app diagnostics flow through these loggers so
/// the in-app "Export Diagnostics" feature can recover a recent activity trail by
/// reading this subsystem back out of `OSLogStore`. See `DiagnosticsExport`.
///
/// Two conventions are baked in here so they can't drift across call sites:
///
/// - **Level.** Always-on breadcrumbs are logged at `.notice` — the lowest level
///   that unified logging persists to disk and that `OSLogStore` can recover after
///   the fact (`.debug`/`.info` cannot). Failures use `.error`. Extra per-cycle
///   verbosity, when enabled, uses `.debug` and is live-only (never relied on for
///   the export).
/// - **Privacy.** A sandboxed app reading its own logs still gets `<private>` for
///   any interpolated value not marked `.public`. The recognized game command is
///   the only dynamic text logged `.public` (low-sensitivity IF input such as
///   "take all"); structural fields are `.public` too since these lines carry no
///   other sensitive content. The typed helpers below are the single home for that
///   decision — nothing outside this file logs raw recognized text.
enum DiagnosticsLog {
  static let subsystem = "com.luminous.diction"

  /// Speech-recognizer lifecycle and post-processing.
  static let asr = Logger(subsystem: subsystem, category: "asr")
  /// Command routing (game / coordinator / ignore).
  static let dispatch = Logger(subsystem: subsystem, category: "dispatch")
  /// Audio route changes and recognizer reconfiguration. Probe for the wedged-
  /// narration investigation: a route change deactivating the session under TTS.
  static let route = Logger(subsystem: subsystem, category: "route")
  /// System-TTS narration state (continuation accounting), same investigation.
  static let tts = Logger(subsystem: subsystem, category: "tts")

  // MARK: - Breadcrumbs (always-on, `.notice` / `.error`)

  /// A capture cycle ended on a final result. `cause` is "final"; `command` is the
  /// recognized text it carried (may be empty).
  static func cycleEnd(cause: String, endpointed: Bool, delivered: Bool, command: String) {
    asr.notice("""
      cycle end (\(cause, privacy: .public)) endpointed=\(endpointed, privacy: .public) \
      delivered=\(delivered, privacy: .public) text=\(command, privacy: .public)
      """)
  }

  /// A capture cycle ended on a recognition error. `cause` carries the error's
  /// domain and code; otherwise as `cycleEnd`.
  static func cycleEndError(cause: String, endpointed: Bool, delivered: Bool, command: String) {
    asr.error("""
      cycle end (\(cause, privacy: .public)) endpointed=\(endpointed, privacy: .public) \
      delivered=\(delivered, privacy: .public) text=\(command, privacy: .public)
      """)
  }

  /// The post-processor's net result: what was heard vs. what it resolved to after
  /// recovery and corrections.
  static func postProcess(heard: String, result: String) {
    asr.notice("post-process \(heard, privacy: .public) → \(result, privacy: .public)")
  }

  /// The routing decision for an input: `.game`, `.coordinator(...)`, or `.ignore`
  /// (with its reason). This is the breadcrumb that explains an "ignored" command
  /// that never reached the parser.
  static func dispatchDecision(text: String, decision: String, fromVoice: Bool) {
    dispatch.notice("""
      decision=\(decision, privacy: .public) fromVoice=\(fromVoice, privacy: .public) \
      text=\(text, privacy: .public)
      """)
  }

  /// The mic input came up with a degenerate format (no capture possible).
  static func micFormatError(_ description: String) {
    asr.error("invalid mic format \(description, privacy: .public); listening off")
  }

  /// A system audio route change: its reason and the resolved output context. Probe
  /// for whether a route change fires mid-narration (the suspected wedge trigger).
  static func routeChange(reason: String, output: String) {
    route.notice("route change reason=\(reason, privacy: .public) output=\(output, privacy: .public)")
  }

  /// The recognizer reconfigure decision on a route/input change: whether listening,
  /// whether the session config moved, and the action taken. A `restart` here while
  /// narration is in flight is the suspected trigger for the leaked TTS continuation.
  static func recognizerReconfigure(listening: Bool, changed: Bool, action: String) {
    route.notice("""
      reconfigure listening=\(listening, privacy: .public) changed=\(changed, privacy: .public) \
      action=\(action, privacy: .public)
      """)
  }

  /// A narration-state transition with the pending-continuation depth. An `enqueue`
  /// (or `speak-begin`) with no matching `didFinish`/`didCancel` (or `speak-end`) is
  /// the leaked continuation that wedges `isSpeaking` true.
  static func ttsEvent(_ event: String, pending: Int, speaking: Bool) {
    tts.notice("""
      \(event, privacy: .public) pending=\(pending, privacy: .public) \
      speaking=\(speaking, privacy: .public)
      """)
  }

  /// A line of the verbose post-processor trace. `.debug`, so it's live-only and
  /// never persisted into the export — for streaming in Xcode/Console while the
  /// DEBUG toggle is on. Keeps the `os` privacy API confined to this file.
  static func verboseTrace(_ line: String) {
    asr.debug("\(line, privacy: .public)")
  }
}
