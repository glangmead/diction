import Foundation

/// Builds the `<style>` block that themes GlkOte's rendered output to match the
/// app's native reading look. GlkOte ships its own stylesheet (`glkote.css`)
/// hardcoding Palatino/15px buffers and an off-white window frame. We append this
/// generated sheet to `<head>` *after* glkote.css, so our equal-specificity
/// `.BufferWindow` selectors win the cascade by appearing later.
///
/// Only the buffer (flowing prose) and the page background are themed here. The
/// grid (status) windows are NOT: GlkOte's own grid is minimised + hidden (see
/// `glk-bridge.html`) and the status bar is rendered natively over the WebView by
/// `StatusWindowView`, which supplies its own theming and fit-to-width sizing.
///
/// Pure by design: every input — the reading font-family, the
/// Dynamic-Type-scaled point size, and the two already-resolved palette hexes — is
/// computed by the caller (`GameView`) for the active typeface/size/colour scheme.
/// That keeps the SwiftUI-aware resolution out of here and makes the generator
/// trivially testable.
enum GlkThemeCSS {
  /// - Parameters:
  ///   - readingFamily: CSS `font-family` for the flowing buffer text (from
  ///     `ReadingTypeface.cssFamily`).
  ///   - pointSize: Effective text size in CSS px — `17 × sizeMultiplier` already
  ///     run through Dynamic Type.
  ///   - textHex: `gameText`, resolved for the active colour scheme. Buffer foreground.
  ///   - backgroundHex: `gameBackground`. The page and the buffer window fill.
  static func stylesheet(
    readingFamily: String,
    pointSize: Double,
    textHex: String,
    backgroundHex: String
  ) -> String {
    let size = formatPx(pointSize)
    return """
    .BufferWindow, .BufferWindow .Input {
      font-family: \(readingFamily);
      font-size: \(size)px;
      color: \(textHex);
    }
    .BufferWindow {
      background-color: \(backgroundHex);
    }
    html, body, #gameport {
      background-color: \(backgroundHex);
    }
    """
  }

  /// Format a px value without a trailing `.0` for whole numbers (so 17 → "17",
  /// 19.5 → "19.5") — purely so the emitted CSS reads cleanly.
  private static func formatPx(_ value: Double) -> String {
    if value == value.rounded() {
      return String(Int(value))
    }
    return String(value)
  }
}
