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

  /// Recompute `isFullVersion` from the verified entitlements StoreKit reports.
  /// `currentEntitlements` is canonical in production, but the local
  /// StoreKit-test environment on device can return it empty even for a
  /// finished, verified non-consumable — so we fall back to the product's latest
  /// transaction, which still surfaces ownership.
  func refreshEntitlement() async {
    var owned = false
    var count = 0
    for await result in Transaction.currentEntitlements {
      count += 1
      switch result {
      case .verified(let transaction):
        print("[store] entitlement[\(count)] verified id=\(transaction.productID) "
          + "revoked=\(String(describing: transaction.revocationDate))")
        if transaction.productID == Self.fullVersionProductID,
           transaction.revocationDate == nil {
          owned = true
        }
      case .unverified(let transaction, let error):
        print("[store] entitlement[\(count)] UNVERIFIED id=\(transaction.productID) error=\(error)")
      }
    }
    if !owned {
      // Production-safe: for an owned non-consumable `latest` is the purchase;
      // a refund sets `revocationDate`, which re-locks.
      if case .verified(let latest)? = await Transaction.latest(for: Self.fullVersionProductID),
         latest.revocationDate == nil {
        print("[store] entitlement via latest(for:) → owned")
        owned = true
      } else {
        print("[store] latest(for:) had no usable transaction")
      }
    }
    print("[store] currentEntitlements count=\(count) owned=\(owned)")
    isFullVersion = owned
    entitlementResolved = true
  }

  /// Unlock directly from a verified transaction in hand — the purchase result
  /// or a `Transaction.updates` push — instead of waiting on a
  /// `currentEntitlements` re-query that returns empty in the local
  /// StoreKit-test environment on device. A set `revocationDate` (refund) re-locks.
  private func grantIfOwned(_ transaction: Transaction) {
    guard transaction.productID == Self.fullVersionProductID else { return }
    isFullVersion = (transaction.revocationDate == nil)
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
        switch verification {
        case .verified(let transaction):
          print("[store] purchase verified id=\(transaction.productID) txn=\(transaction.id)")
          await transaction.finish()
          // Grant from this transaction directly — don't depend on the
          // (empty-here) `currentEntitlements` re-query to flip `isFullVersion`.
          grantIfOwned(transaction)
        case .unverified(let transaction, let error):
          print("[store] purchase UNVERIFIED id=\(transaction.productID) error=\(error)")
          lastError = "Couldn't verify the purchase."
        }
      case .pending:
        // Ask to Buy / SCA: entitlement arrives later via `Transaction.updates`.
        print("[store] purchase pending")
      case .userCancelled:
        print("[store] purchase cancelled")
      @unknown default:
        print("[store] purchase unknown result")
      }
    } catch {
      print("[store] purchase threw: \(error)")
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

  /// A transaction pushed via `Transaction.updates` (refund, remote grant,
  /// Family-Sharing change). Grant/revoke from the verified transaction itself;
  /// only fall back to a full re-derive when it's unverified.
  private func handle(_ result: VerificationResult<Transaction>) async {
    switch result {
    case .verified(let transaction):
      print("[store] update verified id=\(transaction.productID) "
        + "revoked=\(String(describing: transaction.revocationDate))")
      await transaction.finish()
      grantIfOwned(transaction)
    case .unverified:
      print("[store] update unverified — reconciling from entitlements")
      await refreshEntitlement()
    }
  }
}
