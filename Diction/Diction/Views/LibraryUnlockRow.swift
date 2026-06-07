import SwiftUI
import StoreKit

/// A demure, list-row entry to the paywall, shown as its own group beneath the
/// game list. The caller gates visibility (owned / unresolved) and wraps this in
/// a `Section`, so it reads as just another group in the list.
struct LibraryUnlockRow: View {
  @Environment(StoreManager.self) private var store
  let onUnlock: () -> Void

  var body: some View {
    Button(action: onUnlock) {
      LabeledContent {
        if let price = store.product?.displayPrice {
          Text(price).foregroundStyle(.secondary)
        }
      } label: {
        Text("Unlock voice features: premium narration and play-by-voice")
          .foregroundStyle(.primary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityHint("Opens the in-app purchase.")
  }
}
