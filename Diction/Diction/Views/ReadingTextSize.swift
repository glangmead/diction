import CoreGraphics

/// Five semantic size steps for the flowing transcript text. `multiplier` is
/// applied on top of the Dynamic Type-scaled base size, so the user's pick and
/// the device's accessibility text size compound rather than override.
enum ReadingTextSize: Int, CaseIterable, Identifiable {
  case small
  case medium
  case large
  case extraLarge
  case largest

  var id: Int { rawValue }

  /// Human-readable name shown beside the Settings slider.
  var label: String {
    switch self {
    case .small: return "Small"
    case .medium: return "Medium"
    case .large: return "Large"
    case .extraLarge: return "Extra Large"
    case .largest: return "Largest"
    }
  }

  /// Scale factor over the base reading size; `medium` is 1.0 (no change).
  var multiplier: CGFloat {
    switch self {
    case .small: return 0.85
    case .medium: return 1.0
    case .large: return 1.15
    case .extraLarge: return 1.3
    case .largest: return 1.5
    }
  }
}
