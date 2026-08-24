import SwiftUI

extension EnvironmentValues {
  /// Whether a speech recognizer currently owns the shared audio session. Set on
  /// the Settings sheet a game presents, so a neural-voice audition started while
  /// the game is listening leaves the recognizer's session alone
  /// (`NarrationSessionConfig.shouldApply`). Defaults to "no": from the library
  /// there is no recognizer.
  @Entry var isRecognizerLive: @MainActor () -> Bool = { false }
}
