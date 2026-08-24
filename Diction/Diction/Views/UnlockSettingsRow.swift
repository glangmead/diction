import SwiftUI
import StoreKit

/// The Settings entry point to the paywall: an "Unlock all features" row (with
/// price) while in demo, or a "Purchased" indicator once the full version is
/// owned. Owns the paywall sheet it presents.
struct UnlockSettingsRow: View {
  @Environment(StoreManager.self) private var store
  @AppStorage("showLibraryUpgradeButton") private var showLibraryUpgradeButton = true
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
          LabeledContent("Unlock voice features") {
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
        .accessibilityHint("Opens the in-app purchase to unlock the voice features.")
        .sheet(isPresented: $showingPaywall) {
          PaywallView()
        }

        Toggle("Show upgrade button in Library", isOn: $showLibraryUpgradeButton)
      }
    } footer: {
      Text(
        """
        Unlock to narrate with premium neural voices and to play by speaking \
        your commands. Voice commands are free to try in All Things Devours.
        """
      )
    }
  }
}
