import Foundation

/// Loads the resolved `SpeechProfile`: the bundled `global.json` overlaid with an
/// optional user `Documents/SpeechProfiles/global.json` (user wins per the merge
/// rules). Bootstrap-owned `@Observable`, injected via `.environment(...)` so the
/// game view can hand the profile to the synthesizer and coordinator. Global-only
/// in v1 — no per-game keying.
@Observable
@MainActor
final class SpeechProfileStore {
  private(set) var profile: SpeechProfile

  /// - Parameters:
  ///   - bundle: where the bundled `global.json` ships (default `.main`).
  ///   - userDirectory: where a user override `global.json` lives, or nil to skip it.
  init(bundle: Bundle = .main, userDirectory: URL? = SpeechProfileStore.defaultUserDirectory) {
    let base = Self.loadBundled(from: bundle)
    if let userDirectory, let overlay = Self.loadUser(in: userDirectory) {
      profile = base.merging(overlay)
    } else {
      profile = base
    }
  }

  nonisolated static var defaultUserDirectory: URL? {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
      .appendingPathComponent("SpeechProfiles", isDirectory: true)
  }

  private static func loadBundled(from bundle: Bundle) -> SpeechProfile {
    let url = bundle.url(forResource: "global", withExtension: "json", subdirectory: "SpeechProfiles")
      ?? bundle.url(forResource: "global", withExtension: "json")
    guard let url, let data = try? Data(contentsOf: url) else {
      FileHandle.standardError.write(Data("[speech-profile] bundled global.json not found\n".utf8))
      return .empty
    }
    do {
      return try SpeechProfile.decode(data)
    } catch {
      FileHandle.standardError.write(Data("[speech-profile] bundled decode failed: \(error)\n".utf8))
      return .empty
    }
  }

  private static func loadUser(in directory: URL) -> SpeechProfile? {
    let url = directory.appendingPathComponent("global.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    do {
      return try SpeechProfile.decode(data)
    } catch {
      FileHandle.standardError.write(Data("[speech-profile] user decode failed: \(error)\n".utf8))
      return nil
    }
  }
}
