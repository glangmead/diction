import Testing
import Foundation
@testable import Diction

@MainActor
struct LexiconCacheTests {
  /// Mirror the other misaki tests: point the loader at the bundled dicts.
  private func ready() -> Bool {
    guard let root = Bundle.main.url(forResource: "KokoroModels", withExtension: "bundle")?
      .appendingPathComponent("misaki", isDirectory: true) else { return false }
    DataResourcesUtil.bundleURL = root
    return !DataResourcesUtil.loadGold(british: false).isEmpty
  }

  @Test("Same locale returns the same cached instance")
  func sameInstance() {
    #expect(ready())
    let first = LexiconCache.lexicon(british: false)
    let second = LexiconCache.lexicon(british: false)
    #expect(first === second)
  }

  @Test("Different locales are distinct instances")
  func distinctLocales() {
    #expect(ready())
    #expect(LexiconCache.lexicon(british: false) !== LexiconCache.lexicon(british: true))
  }

  @Test("Concurrent callers share one instance")
  func concurrentSameInstance() async {
    #expect(ready())
    let ids = await withTaskGroup(of: ObjectIdentifier.self) { group in
      for _ in 0..<32 { group.addTask { ObjectIdentifier(LexiconCache.lexicon(british: false)) } }
      var set = Set<ObjectIdentifier>()
      for await id in group { set.insert(id) }
      return set
    }
    #expect(ids.count == 1)
  }
}
