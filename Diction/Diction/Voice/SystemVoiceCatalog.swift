import Foundation
import AVFoundation

/// A system (Apple) speech voice, decoupled from `AVSpeechSynthesisVoice` so the
/// grouping/ordering/default logic is pure and testable.
struct SystemVoice: Sendable, Equatable {
  let identifier: String
  let name: String
  /// BCP-47 tag, e.g. "en-US".
  let language: String
  let quality: AVSpeechSynthesisVoiceQuality
}

/// One locale's voices, for the per-locale sections of the picker.
struct SystemVoiceGroup: Identifiable, Equatable {
  /// Full BCP-47 locale tag, e.g. "en-US".
  let localeIdentifier: String
  /// The locale's own name, e.g. "English (United States)", "Français (Canada)".
  let displayName: String
  let voices: [SystemVoice]
  var id: String { localeIdentifier }
}

/// Enumerates and organizes the installed Apple voices, and resolves the default
/// voice used when the user hasn't picked one. All non-`installed()` members are
/// pure functions over `[SystemVoice]`, so the ordering and default selection are
/// unit-testable without constructing `AVSpeechSynthesisVoice`s.
enum SystemVoiceCatalog {
  /// Every installed Apple voice, all languages. `AVSpeechSynthesisVoice.speechVoices()`
  /// is stale within a process — newly downloaded voices appear only after relaunch.
  static func installed() -> [SystemVoice] {
    AVSpeechSynthesisVoice.speechVoices().map {
      SystemVoice(identifier: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality)
    }
  }

  /// The languages the picker offers. iOS ships voices for dozens of languages;
  /// Diction's content is English plus the bundled French and Spanish games, so the
  /// list is scoped to those three rather than overwhelming the user with the rest.
  static let supportedLanguageCodes: Set<String> = ["en", "fr", "es"]

  /// Voices grouped by locale (en-US, en-GB, fr-CA, …): the user's own locale first,
  /// then the rest by locale name. Within a group, highest quality first, then name.
  /// Only `supportedLanguageCodes` are included.
  static func grouped(
    _ voices: [SystemVoice], preferredLocale: String = currentLocaleTag()
  ) -> [SystemVoiceGroup] {
    let supported = voices.filter { supportedLanguageCodes.contains(primaryLanguage($0.language)) }
    let byLocale = Dictionary(grouping: supported, by: \.language)
    let groups = byLocale.map { locale, voices in
      SystemVoiceGroup(
        localeIdentifier: locale,
        displayName: localeDisplayName(for: locale),
        voices: voices.sorted(by: voiceOrder))
    }
    let preferred = normalizeLocale(preferredLocale)
    return groups.sorted { lhs, rhs in
      // The user's own locale first; then everything else by locale name.
      let lhsPreferred = normalizeLocale(lhs.localeIdentifier) == preferred
      let rhsPreferred = normalizeLocale(rhs.localeIdentifier) == preferred
      if lhsPreferred != rhsPreferred { return lhsPreferred }
      return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
  }

  /// The user's current locale as a BCP-47 tag ("en-US"), used to float their own
  /// locale to the top of the list.
  static func currentLocaleTag() -> String {
    Locale.current.identifier(.bcp47)
  }

  private static func normalizeLocale(_ tag: String) -> String {
    tag.replacingOccurrences(of: "_", with: "-").lowercased()
  }

  /// The voice used when the user hasn't explicitly chosen one: the best installed
  /// English voice (Premium → Enhanced → Default). English regardless of device
  /// language, since the content is overwhelmingly English. `nil` only if no English
  /// voice is installed at all.
  static func defaultIdentifier(from voices: [SystemVoice]) -> String? {
    voices
      .filter { primaryLanguage($0.language) == "en" }
      .sorted(by: voiceOrder)
      .first?.identifier
  }

  /// Row text: the voice name, with a quality suffix for Enhanced/Premium (Default
  /// gets none). iOS sometimes bakes the suffix into the name already, so don't double it.
  static func label(for voice: SystemVoice) -> String {
    guard voice.quality != .default else { return voice.name }
    let suffix = "(\(voice.quality.label))"
    return voice.name.hasSuffix(suffix) ? voice.name : "\(voice.name) \(suffix)"
  }

  /// A locale's own name: "en-US" → "English (United States)", "fr-CA" →
  /// "Français (Canada)". A bare language tag yields just the language name.
  static func localeDisplayName(for tag: String) -> String {
    let locale = Locale(identifier: tag)
    let name = locale.localizedString(forIdentifier: tag) ?? tag
    return name.prefix(1).uppercased() + name.dropFirst()
  }

  // MARK: - Ordering

  /// Highest quality first, then name, then locale (so the order is total/stable).
  private static func voiceOrder(_ lhs: SystemVoice, _ rhs: SystemVoice) -> Bool {
    if lhs.quality.rawValue != rhs.quality.rawValue {
      return lhs.quality.rawValue > rhs.quality.rawValue
    }
    if lhs.name != rhs.name {
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
    return lhs.language.localizedStandardCompare(rhs.language) == .orderedAscending
  }

  private static func primaryLanguage(_ tag: String) -> String {
    let primary = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first
    return (primary.map(String.init) ?? tag).lowercased()
  }
}

extension AVSpeechSynthesisVoiceQuality {
  var label: String {
    switch self {
    case .default: "Default"
    case .enhanced: "Enhanced"
    case .premium: "Premium"
    @unknown default: "Unknown"
    }
  }
}
