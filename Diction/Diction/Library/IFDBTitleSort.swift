import Foundation

/// Title-sorting helper for the curated game list: produces a comparison key that
/// ignores a leading article so "The Lurking Horror" files under L and "A Mind
/// Forever Voyaging" under M. Whole-word match only, so "Leather Goddesses" keeps
/// its L and "Lieux Communs" its L.
enum IFDBTitleSort {
  /// Leading articles stripped before comparison. English only by design —
  /// foreign-language titles (e.g. the Spanish "El Museo…") keep their article,
  /// because a blanket multilingual set would mis-sort an English title that merely
  /// starts with a word like "Le" or "El". Extend deliberately if that changes.
  private static let articles: Set<String> = ["the", "a", "an"]

  /// The title minus a single leading article. Case is preserved in the result so
  /// the caller can still collate with `localizedStandardCompare`; only the article
  /// test is case-insensitive. An article-only title (e.g. "The") is left as-is.
  static func sortKey(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespaces)
    guard let space = trimmed.firstIndex(of: " ") else { return trimmed }
    guard articles.contains(trimmed[..<space].lowercased()) else { return trimmed }
    let rest = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
    return rest.isEmpty ? trimmed : rest
  }
}
