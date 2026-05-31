import Foundation

// Loads misaki's gold/silver dictionaries from KokoroModels.bundle/misaki/.
// `bundleURL` is set once by KokoroPhonemizer.load before any EnglishG2P is built.
enum DataResourcesUtil {
  nonisolated(unsafe) static var bundleURL: URL?

  static func loadGold(british: Bool) -> [String: Any] {
    load(british ? "gb_gold" : "us_gold")
  }

  static func loadSilver(british: Bool) -> [String: Any] {
    load(british ? "gb_silver" : "us_silver")
  }

  private static func load(_ filename: String) -> [String: Any] {
    guard let url = bundleURL?.appendingPathComponent("\(filename).json"),
      let data = try? Data(contentsOf: url),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }
    return json
  }
}
