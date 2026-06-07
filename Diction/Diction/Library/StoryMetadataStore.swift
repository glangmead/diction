import Foundation

/// Persists per-game `StoryMetadata` (a JSON map keyed by filename) and caches cover
/// images as files under `Covers/`. Lives in Application Support so covers — which for
/// IFDB downloads can't be re-fetched offline — survive. Used only from the MainActor
/// `StoryFileManager` and from tests, so it needn't be `Sendable`.
final class StoryMetadataStore {
  private let coversDirectory: URL
  private let mapURL: URL
  private var map: [String: StoryMetadata]

  /// `directory` is injectable for tests; production uses Application Support.
  init(directory: URL? = nil) {
    let base = directory ?? Self.defaultDirectory()
    coversDirectory = base.appendingPathComponent("Covers", isDirectory: true)
    mapURL = base.appendingPathComponent("story-metadata.json")
    try? FileManager.default.createDirectory(
      at: coversDirectory, withIntermediateDirectories: true
    )
    map = Self.load(from: mapURL)
  }

  func metadata(for filename: String) -> StoryMetadata? { map[filename] }

  func coverURL(for meta: StoryMetadata) -> URL? {
    meta.coverFilename.map { coversDirectory.appendingPathComponent($0) }
  }

  /// Store `meta` for `filename`, writing `coverImage` (if any) into the covers
  /// directory and recording its name. Returns the stored record (with `coverFilename`).
  @discardableResult
  func setMetadata(_ meta: StoryMetadata, coverImage: Data?, for filename: String) -> StoryMetadata {
    var stored = meta
    if let coverImage {
      let coverName = "\(filename).\(Self.imageExtension(coverImage))"
      try? coverImage.write(to: coversDirectory.appendingPathComponent(coverName))
      stored.coverFilename = coverName
    }
    map[filename] = stored
    persist()
    return stored
  }

  /// Forget a game's metadata and delete its cached cover.
  func remove(for filename: String) {
    if let meta = map[filename], let url = coverURL(for: meta) {
      try? FileManager.default.removeItem(at: url)
    }
    map[filename] = nil
    persist()
  }

  // MARK: - Internals

  private func persist() {
    guard let data = try? JSONEncoder().encode(map) else { return }
    try? data.write(to: mapURL)
  }

  private static func load(from url: URL) -> [String: StoryMetadata] {
    guard let data = try? Data(contentsOf: url),
      let map = try? JSONDecoder().decode([String: StoryMetadata].self, from: data)
    else { return [:] }
    return map
  }

  /// File extension chosen from the image's magic bytes (Blorb covers and IFDB art
  /// are PNG or JPEG).
  private static func imageExtension(_ data: Data) -> String {
    let bytes = [UInt8](data.prefix(3))
    if bytes.count >= 3, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E { return "png" }
    if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xD8 { return "jpg" }
    return "img"
  }

  private static func defaultDirectory() -> URL {
    let base = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("StoryMetadata", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
  }
}
