import Foundation
import StoreKit

/// Owns the single non-consumable IAP and the live full-version entitlement.
/// StoreKit is the source of truth: `Transaction.updates` delivers remote grants,
/// revocations, refunds, and Family-Sharing changes while the app runs. App-level,
/// injected via `.environment` like `VoiceWarmer`.
@Observable
@MainActor
final class StoreManager {
  static let fullVersionProductID = "com.luminous.diction.full"

  private(set) var product: Product?
  private(set) var isFullVersion = false
  /// False until the first `currentEntitlements` pass returns, so the UI can avoid
  /// flashing locks at a returning owner on cold launch.
  private(set) var entitlementResolved = false
  private(set) var isPurchasing = false
  private(set) var lastError: String?

  private var updatesTask: Task<Void, Never>?

  init() {
    // Listen first, so a transaction that arrives mid-launch isn't missed.
    updatesTask = Task { [weak self] in
      for await update in Transaction.updates {
        await self?.handle(update)
      }
    }
    Task { await load() }
  }

  /// Load the product metadata and the initial entitlement.
  func load() async {
    await refreshEntitlement()
    do {
      let products = try await Product.products(for: [Self.fullVersionProductID])
      product = products.first
    } catch {
      lastError = error.localizedDescription
    }
  }

  /// Recompute `isFullVersion` from current verified entitlements.
  func refreshEntitlement() async {
    var owned = false
    for await result in Transaction.currentEntitlements {
      if case .verified(let transaction) = result,
         transaction.productID == Self.fullVersionProductID,
         transaction.revocationDate == nil {
        owned = true
      }
    }
    isFullVersion = owned
    entitlementResolved = true
  }

  func purchase() async {
    guard let product else { return }
    isPurchasing = true
    lastError = nil
    defer { isPurchasing = false }
    do {
      let result = try await product.purchase()
      switch result {
      case .success(let verification):
        if case .verified(let transaction) = verification {
          await transaction.finish()
          await refreshEntitlement()
        } else {
          lastError = "Couldn't verify the purchase."
        }
      case .pending:
        // Ask to Buy / SCA: entitlement arrives later via `Transaction.updates`.
        break
      case .userCancelled:
        break
      @unknown default:
        break
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  func restore() async {
    lastError = nil
    do {
      try await AppStore.sync()
      await refreshEntitlement()
    } catch {
      lastError = error.localizedDescription
    }
  }

  /// A transaction pushed via `Transaction.updates` (renewal, refund, remote
  /// grant). Finish it and re-derive entitlement.
  private func handle(_ result: VerificationResult<Transaction>) async {
    if case .verified(let transaction) = result {
      await transaction.finish()
    }
    await refreshEntitlement()
  }
}
