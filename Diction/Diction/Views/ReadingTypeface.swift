import SwiftUI

/// Typeface for the flowing transcript text (not the monospaced grid/status
/// windows). Each case maps to one of Apple's built-in system font designs:
/// SF Pro, New York, or SF Mono.
enum ReadingTypeface: String, CaseIterable, Identifiable {
  case sansSerif
  case serif
  case monospaced

  var id: String { rawValue }

  /// Human-readable name for the Settings picker.
  var label: String {
    switch self {
    case .sansSerif: return "Sans Serif"
    case .serif: return "Serif"
    case .monospaced: return "Monospaced"
    }
  }

  /// The system font design backing this typeface.
  var design: Font.Design {
    switch self {
    case .sansSerif: return .default
    case .serif: return .serif
    case .monospaced: return .monospaced
    }
  }

  /// CSS `font-family` value backing this typeface in the GlkOte WebView. These
  /// are semantic/generic families that iOS resolves to the same system fonts
  /// `design` does — `-apple-system` → SF Pro, `ui-serif` → New York, and
  /// `ui-monospace` → SF Mono — so we never hardcode a concrete face name (which
  /// would skip the OS's font substitution and Dynamic Type metrics).
  var cssFamily: String {
    switch self {
    case .sansSerif: return "-apple-system, system-ui, sans-serif"
    case .serif: return "ui-serif, Georgia, serif"
    case .monospaced: return "ui-monospace, Menlo, monospace"
    }
  }
}
