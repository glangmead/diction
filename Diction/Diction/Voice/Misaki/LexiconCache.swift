import Foundation

/// Process-wide cache of built `Lexicon`s. Building one parses the ~3MB gold +
/// silver JSON and grows it; `KokoroPhonemizer.phonemize` used to do that twice
/// per sentence on the main actor (a ~480ms hang). The key includes the active
/// `DataResourcesUtil.bundleURL` because the dictionaries are read relative to
/// it and it is `nil` until set — so a build done while it is `nil` (empty
/// dicts, e.g. early in a parallel test run) can't poison the populated entry.
/// In production `bundleURL` is set once, so all calls hit a single entry.
enum LexiconCache {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var cache: [String: Lexicon] = [:]

  static func lexicon(british: Bool) -> Lexicon {
    let key = "\(british)|\(DataResourcesUtil.bundleURL?.path ?? "")"
    lock.lock()
    defer { lock.unlock() }
    if let cached = cache[key] { return cached }
    let built = Lexicon(british: british)
    cache[key] = built
    return built
  }
}
