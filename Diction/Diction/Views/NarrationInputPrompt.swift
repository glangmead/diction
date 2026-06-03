import Foundation

/// Presentation logic for the game input bar's "listening paused" placeholder.
///
/// While narration plays, `VoiceCoordinator.decide` drops bare spoken commands
/// (only wake-word commands like "game stop" interrupt), so the input bar tells
/// the user their plain spoken command won't land right now — and how to stop
/// the narration. Pure and view-independent so the show/hide rule and wording
/// are unit-testable without a live coordinator.
enum NarrationInputPrompt {
  /// Whether to show the prompt. True only while narrating *and* the user hasn't
  /// tapped into the field — typing shouldn't be nagged.
  static func isVisible(isNarrating: Bool, isFieldFocused: Bool) -> Bool {
    isNarrating && !isFieldFocused
  }

  /// Placeholder text shown while narrating. `wakeWord` is the already-resolved
  /// wake word (caller passes `VoiceCoordinator.wakeWord`, which normalizes
  /// empty → "game"), so a custom wake word appears in the interrupt hint.
  static func message(wakeWord: String) -> String {
    "(Narrating)"
  }
}
