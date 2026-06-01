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
}
