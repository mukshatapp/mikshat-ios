import Combine
import Foundation
import StoreKit
import UIKit

enum MikshatSubscriptionText {
  static func text(ar: String, en: String) -> String {
    let language = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "ar"
    return language.hasPrefix("ar") ? ar : en
  }
}

/// Access comes only from Apple's verified transactions. Loading the storefront product is separate
/// so an offline customer keeps access until the verified subscription's actual expiration date.
@MainActor
final class MikshatSubscriptionStore: ObservableObject {
  static let shared = MikshatSubscriptionStore()
  static let productID = "com.mikshat.maps.premium.annual"

  @Published private(set) var product: Product?
  @Published private(set) var isBusy = false
  @Published private(set) var message: String?
  @Published private(set) var isCheckingEntitlements = true
  @Published private var entitlements: [UInt64: MikshatSubscriptionEntitlement] = [:]

  var expirationDate: Date? {
    MikshatSubscriptionEntitlement.activeExpiration(in: Array(entitlements.values),
                                                  productID: Self.productID, at: Date())
  }
  var hasActiveSubscription: Bool { expirationDate != nil }

  private var started = false
  private var revision: UInt64 = 0
  private var updatesTask: Task<Void, Never>?
  private var entitlementRefreshTask: Task<Void, Never>?
  private var productLoadTask: Task<Void, Never>?
  private var foregroundObserver: NSObjectProtocol?
  private var expirationTimer: Timer?

  private static var productUnavailableMessage: String {
    MikshatSubscriptionText.text(ar: "الاشتراك غير متاح حاليًا في المتجر. حاول لاحقًا.",
                                 en: "The subscription is currently unavailable in the App Store. Please try again later.")
  }

  private static var productConnectionMessage: String {
    MikshatSubscriptionText.text(ar: "تعذر الاتصال بمتجر Apple. تحقق من الاتصال وحاول مجددًا.",
                                 en: "Could not connect to the App Store. Check your connection and try again.")
  }

  private init() {}

  func start() {
    guard !started else { return }
    started = true
    updatesTask = Task { [weak self] in
      for await result in StoreKit.Transaction.updates {
        guard !Task.isCancelled, let self else { return }
        switch result {
        case .verified(let transaction):
          guard self.accepts(transaction) else { continue }
          self.record(transaction)
          await transaction.finish()
          await self.refreshEntitlements()
        case .unverified:
          // An unverified transaction must never unlock access or be acknowledged as delivered.
          self.message = MikshatSubscriptionText.text(
            ar: "تعذر التحقق من الاشتراك لدى Apple. جرّب استعادة المشتريات.",
            en: "Apple could not verify the subscription. Try restoring purchases.")
        }
      }
    }
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in await self?.refreshEntitlements() }
    }
    Task { [weak self] in
      guard let self else { return }
      await self.refreshEntitlements()
      await self.loadProduct()
    }
  }

  func refreshEntitlements() async {
    if let entitlementRefreshTask { await entitlementRefreshTask.value; return }
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.scanEntitlements()
    }
    // All callers await the same applied snapshot, rather than racing an unfinished initial scan.
    entitlementRefreshTask = task
    await task.value
    entitlementRefreshTask = nil
  }

  private func scanEntitlements() async {
    revision &+= 1
    let snapshotRevision = revision
    isCheckingEntitlements = true
    var verified: [UInt64: MikshatSubscriptionEntitlement] = [:]
    for await result in StoreKit.Transaction.currentEntitlements {
      guard !Task.isCancelled else {
        if revision == snapshotRevision { isCheckingEntitlements = false }
        return
      }
      if case .verified(let transaction) = result, accepts(transaction) {
        verified[transaction.id] = entitlement(for: transaction)
      }
    }
    // A purchase/update received while scanning is newer than this snapshot.
    guard revision == snapshotRevision else { return }
    entitlements = verified
    isCheckingEntitlements = false
    scheduleExpirationRefresh()
  }

  func loadProduct() async {
    if let productLoadTask { await productLoadTask.value; return }
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      let messageBeforeLookup = self.message
      do {
        let products = try await Product.products(for: [Self.productID])
        guard let annual = products.first(where: { product in
          guard product.id == Self.productID, product.type == .autoRenewable,
                let period = product.subscription?.subscriptionPeriod else { return false }
          return period.unit == .year && period.value == 1
        }) else {
          self.product = nil
          if self.message == messageBeforeLookup { self.message = Self.productUnavailableMessage }
          return
        }
        self.product = annual
        // Clear this lookup's old error without dismissing a newer pending-purchase message.
        if self.message == Self.productUnavailableMessage || self.message == Self.productConnectionMessage {
          self.message = nil
        }
      } catch is CancellationError {
        return
      } catch {
        if self.message == messageBeforeLookup { self.message = Self.productConnectionMessage }
      }
    }
    productLoadTask = task
    await task.value
    productLoadTask = nil
  }

  @discardableResult
  func purchase() async -> Bool {
    guard !isBusy else { return false }
    start()
    isBusy = true
    message = nil
    defer { isBusy = false }
    await refreshEntitlements()
    if hasActiveSubscription { return true }
    if product == nil { await loadProduct() }
    guard let product else { return false }
    do {
      switch try await product.purchase() {
      case .success(let result):
        guard case .verified(let transaction) = result, accepts(transaction) else {
          message = MikshatSubscriptionText.text(
            ar: "لم تتمكن Apple من تأكيد الشراء. لم تُفتح المزايا؛ جرّب استعادة المشتريات.",
            en: "Apple could not verify the purchase. Features remain locked; try restoring purchases.")
          return false
        }
        record(transaction)
        await transaction.finish()
        // The verified purchase itself grants access even before it appears in a later snapshot.
        return hasActiveSubscription
      case .pending:
        message = MikshatSubscriptionText.text(
          ar: "الشراء بانتظار موافقة Apple. ستُفعّل المزايا بعد تأكيده.",
          en: "The purchase is awaiting approval. Features will unlock when Apple confirms it.")
        return false
      case .userCancelled:
        return false
      @unknown default:
        message = MikshatSubscriptionText.text(ar: "لم يكتمل الشراء. حاول مجددًا.",
                                               en: "The purchase did not complete. Please try again.")
        return false
      }
    } catch is CancellationError {
      return false
    } catch {
      message = MikshatSubscriptionText.text(ar: "تعذر إتمام الشراء من Apple. حاول مجددًا.",
                                             en: "The App Store purchase could not be completed. Please try again.")
      return false
    }
  }

  @discardableResult
  func restore() async -> Bool {
    guard !isBusy else { return false }
    start()
    isBusy = true
    message = nil
    defer { isBusy = false }
    do {
      // Explicit user action only: sync can ask the user to authenticate with the App Store.
      try await AppStore.sync()
      await refreshEntitlements()
      if !hasActiveSubscription {
        message = MikshatSubscriptionText.text(ar: "لا يوجد اشتراك سنوي نشط لاستعادته لهذا الحساب.",
                                               en: "No active annual subscription was found for this App Store account.")
      }
    } catch is CancellationError {
      return false
    } catch {
      // A failed network restore must not remove an already verified, unexpired entitlement.
      message = MikshatSubscriptionText.text(ar: "تعذرت استعادة المشتريات. تحقق من الاتصال وحاول مجددًا.",
                                             en: "Purchases could not be restored. Check your connection and try again.")
    }
    return hasActiveSubscription
  }

  private func accepts(_ transaction: StoreKit.Transaction) -> Bool {
    transaction.productID == Self.productID && transaction.productType == .autoRenewable
  }

  private func entitlement(for transaction: StoreKit.Transaction) -> MikshatSubscriptionEntitlement {
    MikshatSubscriptionEntitlement(productID: transaction.productID,
                                  expirationDate: transaction.expirationDate,
                                  revocationDate: transaction.revocationDate,
                                  isUpgraded: transaction.isUpgraded,
                                  isAutoRenewable: transaction.productType == .autoRenewable,
                                  isVerified: true)
  }

  private func record(_ transaction: StoreKit.Transaction) {
    revision &+= 1
    entitlements[transaction.id] = entitlement(for: transaction)
    isCheckingEntitlements = false
    scheduleExpirationRefresh()
  }

  private func scheduleExpirationRefresh() {
    expirationTimer?.invalidate()
    expirationTimer = nil
    guard let expirationDate else { return }
    expirationTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, expirationDate.timeIntervalSinceNow + 0.05),
                                           repeats: false) { [weak self] _ in
      Task { @MainActor [weak self] in await self?.refreshEntitlements() }
    }
  }

  deinit {
    updatesTask?.cancel()
    entitlementRefreshTask?.cancel()
    productLoadTask?.cancel()
    expirationTimer?.invalidate()
    if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
  }
}
