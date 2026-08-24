import SwiftUI

/// Shown when the interpreter is blocked on a single-keypress input
/// (`glk_request_char_event`). The field auto-submits each keystroke via `onKey`;
/// "Continue" sends a space ("press SPACE to begin"); Return sends a Return
/// keypress so char-driven forms (Bureaucracy) can advance to the next field.
struct CharInputBar: View {
  var inputFocused: FocusState<Bool>.Binding
  /// The "listening paused" placeholder, or nil when it shouldn't show.
  let narrationPausedText: String?
  let onKey: (String) -> Void

  /// Owned here, separate from the line field's `commandText`: this field
  /// auto-submits on every character, and that behaviour must not leak into the
  /// line field when the mode flips back.
  @State private var charInputText = ""

  /// Visual + VoiceOver hint for the single-keypress field.
  private static let hint = "y / n / 1 / …"

  var body: some View {
    HStack(spacing: 8) {
      Text("Key:")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gray)
      TextField("", text: $charInputText, prompt: Text(narrationPausedText ?? Self.hint))
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gameText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused(inputFocused)
        .submitLabel(.return)
        .accessibilityLabel("Press a single key")
        .accessibilityValue(narrationPausedText ?? (charInputText.isEmpty ? Self.hint : charInputText))
        .onChange(of: charInputText) { _, new in
          guard let first = new.first else { return }
          let key = String(first)
          charInputText = ""
          onKey(key)
        }
        .onSubmit { onKey("return") }
      Button("Continue") {
        onKey(" ")
      }
      .buttonStyle(.borderedProminent)
      .accessibilityHint("Sends space; the most common 'press any key' answer.")
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.gameSurface)
  }
}
