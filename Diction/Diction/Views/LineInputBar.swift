import SwiftUI

/// The `>` prompt and command field shown while the interpreter wants a line of
/// input. Submitting hands the text to `onSubmit`; a swipe down on the bar (or the
/// "Hide keyboard" accessibility action) calls `onDismissKeyboard` so the owner can
/// drop focus without submitting.
struct LineInputBar: View {
  @Binding var commandText: String
  var inputFocused: FocusState<Bool>.Binding
  /// The "listening paused" placeholder, or nil when it shouldn't show.
  let narrationPausedText: String?
  let onSubmit: () -> Void
  let onDismissKeyboard: () -> Void

  /// The measured height of one line of the input font (taken from the stable `>`
  /// prompt), used to pin the field's height. A `UITextField` reports a ~2 pt
  /// taller intrinsic height once it holds text than when empty, so a bare
  /// `TextField` makes the bar grow the moment a command appears; because the bar
  /// shares a `VStack(spacing: 0)` with the greedy WebView, that shrinks the WebView
  /// and slides its bottom-pinned log up for as long as text is present.
  /// (Device-only — the Simulator's font metrics don't show the padding.) Pinning
  /// the field to the prompt's line height keeps empty and filled identical.
  @State private var inputLineHeight: CGFloat?

  var body: some View {
    HStack(spacing: 8) {
      Text(">")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gray)
        // The prompt is a stable single line of the input font, so its measured
        // height is the line height to pin the field to (see `inputLineHeight`).
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { inputLineHeight = $0 }
      TextField("", text: $commandText, prompt: narrationPausedText.map { Text($0) })
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.gameText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        // Pin to the prompt's line height so a filled field doesn't measure ~2 pt
        // taller than an empty one and grow the bar — which slid the log (see
        // `inputLineHeight`). nil until first measured, then fixed.
        .frame(height: inputLineHeight)
        .focused(inputFocused)
        .onSubmit(onSubmit)
        .submitLabel(.send)
        .accessibilityLabel("Enter command")
        .accessibilityValue(narrationPausedText ?? commandText)
        // VoiceOver / Voice Control equivalent of the swipe-down dismiss below.
        .accessibilityAction(named: "Hide keyboard", onDismissKeyboard)
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.gameSurface)
    // Swipe the input bar down to close the keyboard without submitting. The log
    // scrolls internally, so there's no outer scrollview for the system's
    // swipe-to-dismiss; this gesture on the native bar provides it. The minimum
    // distance leaves taps and typing alone.
    .simultaneousGesture(
      DragGesture(minimumDistance: 20)
        .onEnded { value in
          if value.translation.height > 40,
             value.translation.height > abs(value.translation.width) {
            onDismissKeyboard()
          }
        }
    )
  }
}
