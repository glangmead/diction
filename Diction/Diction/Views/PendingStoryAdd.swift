import Foundation

/// A downloaded or picked story file that is byte-identical to one already in the
/// library, staged while the user confirms whether to add a second copy. Holds the
/// staged temp file plus the names shown in the confirmation dialog. The temp file
/// lives in its own directory; cancel or commit both remove that directory.
struct PendingStoryAdd: Identifiable {
  let id = UUID()
  /// The staged file to add (a temp copy, so it outlives any security scope).
  let sourceURL: URL
  /// Preferred library name, or nil to use `sourceURL`'s filename.
  let preferredName: String?
  /// Title of the existing library game it duplicates (for the dialog message).
  let existingTitle: String
  /// Title of the incoming game (for the dialog message).
  let displayTitle: String
  /// Catalog metadata (e.g. from IFDB) to overlay on the file-derived metadata when
  /// the copy is committed. Nil for plain file adds.
  var supplemental: StoryMetadata?
  /// Cover image bytes (e.g. fetched from IFDB) to cache when the copy is committed.
  var coverImage: Data?
}
