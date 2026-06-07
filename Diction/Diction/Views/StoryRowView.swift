import SwiftUI

/// One library row. With extracted/looked-up `metadata` it shows a cover thumbnail
/// (or a title-initial placeholder), the official title, author · year, a one-line
/// headline, and the engine version appended to the format/source chips. Without
/// metadata — games added before this existed, and the bundled game — it falls back
/// to the original image-less row.
struct StoryRowView: View {
  let story: StoryFile
  let locked: Bool
  /// Cached cover-image URL, or nil for bare files and rows without metadata.
  let coverURL: URL?

  @ScaledMetric(relativeTo: .body) private var coverSize: CGFloat = 52

  private var hasMetadata: Bool { story.metadata != nil }
  private var displayTitle: String { story.metadata?.title ?? story.title }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      if hasMetadata {
        cover
      }
      VStack(alignment: .leading, spacing: 4) {
        titleLine
        if let subtitle = authorYear {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        if let headline = story.metadata?.headline, !headline.isEmpty {
          Text(headline)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        chips
        LibraryStatusPreview(url: story.url, lastPlayed: story.lastPlayed)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  // MARK: - Pieces

  private var titleLine: some View {
    HStack {
      Text(displayTitle)
        .font(.headline)
      Spacer(minLength: 8)
      if locked {
        Image(systemName: "lock.fill")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    }
  }

  private var chips: some View {
    HStack(spacing: 8) {
      Text(story.format == .zMachine ? "Z-machine" : "Glulx")
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
          Capsule()
            .fill(story.format == .zMachine ? .blue : .purple)
            .opacity(0.2)
        )
      Text(story.source.label)
        .font(.caption)
        .foregroundStyle(.secondary)
      if let version = story.metadata?.versionLabel {
        Text("· \(version)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
  }

  @ViewBuilder
  private var cover: some View {
    Group {
      if let coverURL {
        AsyncImage(url: coverURL) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            placeholder
          }
        }
      } else {
        placeholder
      }
    }
    .frame(width: coverSize, height: coverSize)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(.secondary.opacity(0.2))
    )
    .accessibilityHidden(true)
  }

  /// Coverless games get a fixed gray tile with the title's uppercase first letter in
  /// fixed black. Both colors are fixed (not semantic) so the tile looks the same in
  /// light and dark — the box never darkens, so black stays legible.
  private var placeholder: some View {
    ZStack {
      Rectangle().fill(Color(white: 0.85))
      Text(displayTitle.first.map { String($0).uppercased() } ?? "?")
        .font(.title.weight(.semibold))
        .foregroundStyle(.black)
    }
  }

  // MARK: - Derived text

  private var authorYear: String? {
    switch (story.metadata?.author, story.metadata?.year) {
    case let (author?, year?): return "by \(author) · \(year)"
    case let (author?, nil): return "by \(author)"
    case let (nil, year?): return year
    default: return nil
    }
  }

  private var accessibilityLabel: String {
    var parts: [String] = [displayTitle]
    if let author = story.metadata?.author { parts.append("by \(author)") }
    if let year = story.metadata?.year { parts.append(year) }
    parts.append(story.format == .zMachine ? "Z-machine" : "Glulx")
    parts.append(story.source.label)
    if let version = story.metadata?.versionLabel { parts.append(version) }
    if story.lastPlayed != nil { parts.append("recently played") }
    if locked { parts.append("locked, double tap to unlock") }
    return parts.joined(separator: ", ")
  }
}
