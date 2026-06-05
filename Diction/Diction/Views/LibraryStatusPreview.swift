import SwiftUI

/// The last saved status bar for a played game, shown compactly inside its
/// library row. Reads the small status artifact `GameSnapshotStore` persists each
/// turn — nil for never-played games or games without a status window, so those
/// rows are unchanged. Loaded in `.task` (off the render path) and refreshed
/// whenever the game's last-played time changes, i.e. after you play it again.
struct LibraryStatusPreview: View {
  let url: URL
  let lastPlayed: Date?

  @State private var windows: [GridWindowSnapshot] = []

  /// Compact preview cap — a row shows a small status, not the live reading size.
  private static let previewFontSize: CGFloat = 11

  var body: some View {
    // The VStack is always present (empty → zero-size) so `.task` runs and loads
    // the artifact even before any rows exist; `StatusWindowView` fits each to the
    // row width and `GridReflow` compacts the wide saved padding.
    VStack(spacing: 0) {
      ForEach(windows) { window in
        StatusWindowView(window: window, maxFontSizeOverride: Self.previewFontSize, showsSeparator: false)
      }
    }
    .clipShape(.rect(cornerRadius: 6))
    .accessibilityHidden(true)
    .task(id: lastPlayed) {
      windows = GameSnapshotStore.default.readStatus(gameID: SaveStorage.gameID(for: url)) ?? []
    }
  }
}
