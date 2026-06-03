import SwiftUI
import StoreKit

/// The Settings entry point to the paywall: an "Unlock all features" row (with
/// price) while in demo, or a "Purchased" indicator once the full version is
/// owned. Owns the paywall sheet it presents.
struct UnlockSettingsRow: View {
  @Environment(StoreManager.self) private var store
  @State private var showingPaywall = false

  var body: some View {
    Section {
      if store.isFullVersion {
        LabeledContent("Full version") {
          Label("Purchased", systemImage: "checkmark.seal.fill")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.green)
        }
      } else {
        Button {
          showingPaywall = true
        } label: {
          LabeledContent("Unlock all features") {
            HStack(spacing: 6) {
              if let price = store.product?.displayPrice {
                Text(price).foregroundStyle(.secondary)
              }
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the in-app purchase to play any game and use any voice.")
        .sheet(isPresented: $showingPaywall) {
          PaywallView()
        }
      }
    } footer: {
      Text(
        """
        Demo plays the bundled game and four narration voices. Unlock to play \
        any game you add and use every voice.
        """
      )
    }
  }
}
