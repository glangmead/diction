import SwiftUI

/// A demure entry to the paywall, shown as its own group beneath the game list.
/// Reads as a tinted (accent-colour) line of tappable text — SwiftUI's text-button
/// look — with no row-button chrome (the caller clears the cell fill). The caller
/// gates visibility (owned / unresolved) and wraps this in a `Section`.
struct LibraryUnlockRow: View {
  let onUnlock: () -> Void

  var body: some View {
    Button(action: onUnlock) {
      Text("Unlock voice features")
        .font(.footnote)
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityHint("Opens the in-app purchase.")
  }
}
