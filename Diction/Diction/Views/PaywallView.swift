import SwiftUI
import StoreKit

/// The single paywall, presented as a sheet from a locked game tap, a locked
/// voice tap, and the Settings "Unlock" row. Reads the shared `StoreManager`
/// from the environment; dismisses itself the moment the purchase lands.
struct PaywallView: View {
  @Environment(StoreManager.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          header
          featureList
          actions
        }
        .padding()
        .frame(maxWidth: .infinity)
      }
      .navigationTitle("Unlock all features")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
      .onChange(of: store.isFullVersion) { _, full in
        if full { dismiss() }
      }
    }
  }

  private var header: some View {
    VStack(spacing: 8) {
      Image(systemName: "books.vertical.fill")
        .font(.system(size: 48))
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      Text("Unlock all features")
        .font(.title2.bold())
      Text("Play every game you add, and use every narration voice.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  private var featureList: some View {
    VStack(alignment: .leading, spacing: 12) {
      feature("play.circle.fill", "Play any game you import or download from IFDB")
      feature("waveform", "Use every neural narration voice")
      feature("infinity", "One-time purchase — no subscription")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func feature(_ symbol: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: symbol)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      Text(text)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var actions: some View {
    if store.product == nil {
      ProgressView()
        .padding()
        .accessibilityLabel("Loading purchase options")
    } else {
      Button {
        Task { await store.purchase() }
      } label: {
        Group {
          if store.isPurchasing {
            ProgressView()
              .accessibilityLabel("Purchasing")
          } else {
            Text("Unlock — \(store.product?.displayPrice ?? "")")
          }
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(store.isPurchasing)

      Button("Restore Purchases") {
        Task { await store.restore() }
      }
      .disabled(store.isPurchasing)

      if let error = store.lastError {
        Text(error)
          .font(.footnote)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }
    }
  }
}
