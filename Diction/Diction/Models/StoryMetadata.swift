import Foundation

/// Presentation metadata for a story file: official title, author, year, headline,
/// a version label (Z-machine release/serial or Glulx version), and the filename of a
/// cached cover image. All optional — a bare story file yields only a version label,
/// while a Blorb or an IFDB download can supply the rest.
struct StoryMetadata: Codable, Sendable, Equatable {
  var title: String?
  var author: String?
  var year: String?
  var headline: String?
  var versionLabel: String?
  var coverFilename: String?

  /// Overlay `other` (e.g. richer IFDB data) onto self: each of `other`'s non-nil
  /// fields wins — except `versionLabel`, which stays self's, because the file is the
  /// authoritative source for the engine version regardless of catalog metadata.
  func merging(_ other: StoryMetadata?) -> StoryMetadata {
    guard let other else { return self }
    return StoryMetadata(
      title: other.title ?? title,
      author: other.author ?? author,
      year: other.year ?? year,
      headline: other.headline ?? headline,
      versionLabel: versionLabel ?? other.versionLabel,
      coverFilename: other.coverFilename ?? coverFilename
    )
  }
}
