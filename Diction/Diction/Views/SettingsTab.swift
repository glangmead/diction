import Foundation

/// The two segments of the Settings sheet's top picker.
enum SettingsTab: String, CaseIterable, Identifiable {
  case settings
  case about

  var id: String { rawValue }

  var label: String {
    switch self {
    case .settings: "Settings"
    case .about: "About"
    }
  }
}
