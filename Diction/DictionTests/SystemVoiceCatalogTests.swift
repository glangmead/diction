import Foundation
import AVFoundation
import Testing
@testable import Diction

@Suite("System voice catalog")
struct SystemVoiceCatalogTests {
  private func voice(
    _ identifier: String, _ name: String, _ language: String,
    _ quality: AVSpeechSynthesisVoiceQuality
  ) -> SystemVoice {
    SystemVoice(identifier: identifier, name: name, language: language, quality: quality)
  }

  @Test("the user's own locale is listed first, then the rest alphabetically")
  func groupOrder() {
    let voices = [
      voice("es1", "Mónica", "es-ES", .enhanced),
      voice("en1", "Ava", "en-US", .premium),
      voice("fr1", "Thomas", "fr-FR", .enhanced)
    ]
    #expect(SystemVoiceCatalog.grouped(voices, preferredLocale: "fr-FR").map(\.localeIdentifier)
      == ["fr-FR", "en-US", "es-ES"])
    #expect(SystemVoiceCatalog.grouped(voices, preferredLocale: "en-US").map(\.localeIdentifier)
      == ["en-US", "es-ES", "fr-FR"])
  }

  @Test("the preferred-locale match tolerates underscore/case differences")
  func preferredLocaleNormalized() {
    let voices = [voice("a", "Ava", "en-US", .premium), voice("t", "Thomas", "fr-FR", .enhanced)]
    #expect(SystemVoiceCatalog.grouped(voices, preferredLocale: "fr_FR").first?.localeIdentifier == "fr-FR")
  }

  @Test("only English, French, and Spanish voices are listed")
  func filtersUnsupportedLanguages() {
    let groups = SystemVoiceCatalog.grouped([
      voice("en", "Ava", "en-US", .premium),
      voice("de", "Anna", "de-DE", .enhanced),
      voice("ja", "Kyoko", "ja-JP", .enhanced),
      voice("fr", "Thomas", "fr-FR", .enhanced)
    ], preferredLocale: "en-US")
    #expect(groups.map(\.localeIdentifier) == ["en-US", "fr-FR"])
  }

  @Test("each locale is its own group, highest quality first within it")
  func withinLocaleOrder() {
    let groups = SystemVoiceCatalog.grouped([
      voice("s", "Samantha", "en-US", .enhanced),
      voice("d", "Daniel", "en-GB", .default),
      voice("a", "Ava", "en-US", .premium)
    ], preferredLocale: "zz-ZZ")   // no match → pure alphabetical
    #expect(groups.map(\.localeIdentifier) == ["en-GB", "en-US"])
    #expect(groups.first { $0.localeIdentifier == "en-US" }?.voices.map(\.name) == ["Ava", "Samantha"])
  }

  @Test("the default is the best English voice, ignoring other languages")
  func defaultIsBestEnglish() {
    let id = SystemVoiceCatalog.defaultIdentifier(from: [
      voice("s", "Samantha", "en-US", .enhanced),
      voice("a", "Ava", "en-US", .premium),
      voice("t", "Thomas", "fr-FR", .premium)
    ])
    #expect(id == "a")
  }

  @Test("there is no default when no English voice is installed")
  func noEnglishNoDefault() {
    #expect(SystemVoiceCatalog.defaultIdentifier(from: [
      voice("t", "Thomas", "fr-FR", .premium)
    ]) == nil)
  }

  @Test("the row label appends quality for Enhanced/Premium but not Default")
  func rowLabel() {
    #expect(SystemVoiceCatalog.label(for: voice("a", "Ava", "en-US", .premium)) == "Ava (Premium)")
    #expect(SystemVoiceCatalog.label(for: voice("d", "Daniel", "en-GB", .default)) == "Daniel")
    // iOS sometimes bakes the quality into the name; don't double it.
    #expect(SystemVoiceCatalog.label(
      for: voice("s", "Samantha (Enhanced)", "en-US", .enhanced)) == "Samantha (Enhanced)")
  }

  @Test("locale display names read 'Language (Region)' in the locale's own language")
  func localeName() {
    #expect(SystemVoiceCatalog.localeDisplayName(for: "en-US") == "English (United States)")
  }
}
