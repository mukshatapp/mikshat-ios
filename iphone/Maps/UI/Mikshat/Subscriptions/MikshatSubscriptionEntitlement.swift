import Foundation

/// A value extracted from StoreKit's verification result, independent of product lookup or UI.
struct MikshatSubscriptionEntitlement: Equatable {
  let productID: String
  let expirationDate: Date?
  let revocationDate: Date?
  let isUpgraded: Bool
  let isAutoRenewable: Bool
  let isVerified: Bool

  func grantsAccess(to expectedProductID: String, at date: Date) -> Bool {
    guard isVerified, isAutoRenewable, productID == expectedProductID,
          revocationDate == nil, !isUpgraded, let expirationDate else { return false }
    return expirationDate > date
  }

  static func activeExpiration(in entitlements: [Self], productID: String, at date: Date) -> Date? {
    entitlements.filter { $0.grantsAccess(to: productID, at: date) }
      .compactMap(\.expirationDate)
      .max()
  }
}
