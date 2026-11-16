#if !os(Linux)
@testable import Organic_Maps__Debug_
#endif
import Foundation
import XCTest

final class MikshatSubscriptionEntitlementTests: XCTestCase {
  private let productID = "com.mikshat.maps.premium.annual"
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func entitlement(product: String? = nil, expiration: Date? = nil, revoked: Date? = nil,
                           upgraded: Bool = false, renewable: Bool = true,
                           verified: Bool = true) -> MikshatSubscriptionEntitlement {
    MikshatSubscriptionEntitlement(productID: product ?? productID,
                                  expirationDate: expiration ?? now.addingTimeInterval(3_600),
                                  revocationDate: revoked, isUpgraded: upgraded,
                                  isAutoRenewable: renewable, isVerified: verified)
  }

  func testVerifiedUnexpiredAnnualTransactionGrantsAccessWithoutAStorefrontProduct() {
    XCTAssertTrue(entitlement().grantsAccess(to: productID, at: now))
  }

  func testUnverifiedTransactionNeverGrantsAccess() {
    XCTAssertFalse(entitlement(verified: false).grantsAccess(to: productID, at: now))
  }

  func testAnotherProductCannotUnlockMembership() {
    XCTAssertFalse(entitlement(product: "another.product").grantsAccess(to: productID, at: now))
  }

  func testExpiredAndExactExpirationDateDoNotGrantAccess() {
    XCTAssertFalse(entitlement(expiration: now.addingTimeInterval(-1)).grantsAccess(to: productID, at: now))
    XCTAssertFalse(entitlement(expiration: now).grantsAccess(to: productID, at: now))
  }

  func testPreviouslyVerifiedEntitlementIsReevaluatedWhenTimePasses() {
    let subscription = entitlement(expiration: now.addingTimeInterval(60))
    XCTAssertTrue(subscription.grantsAccess(to: productID, at: now))
    XCTAssertFalse(subscription.grantsAccess(to: productID, at: now.addingTimeInterval(61)))
  }

  func testRefundOrRevocationImmediatelyRemovesAccess() {
    XCTAssertFalse(entitlement(revoked: now.addingTimeInterval(-10)).grantsAccess(to: productID, at: now))
  }

  func testReplacedUpgradeTransactionDoesNotGrantAccess() {
    XCTAssertFalse(entitlement(upgraded: true).grantsAccess(to: productID, at: now))
  }

  func testOtherProductTypesCannotGrantAnnualSubscriptionAccess() {
    XCTAssertFalse(entitlement(renewable: false).grantsAccess(to: productID, at: now))
  }

  func testTransactionWithoutAnExpirationCannotGrantAnnualAccess() {
    let noExpiration = MikshatSubscriptionEntitlement(productID: productID, expirationDate: nil,
                                                     revocationDate: nil, isUpgraded: false,
                                                     isAutoRenewable: true, isVerified: true)
    XCTAssertFalse(noExpiration.grantsAccess(to: productID, at: now))
  }

  func testLatestValidRenewalWinsOverExpiredRevokedAndForeignTransactions() {
    let renewal = now.addingTimeInterval(7_200)
    let transactions = [entitlement(), entitlement(expiration: renewal),
                        entitlement(expiration: now), entitlement(revoked: now),
                        entitlement(product: "another.product", expiration: now.addingTimeInterval(99_999)),
                        entitlement(expiration: now.addingTimeInterval(88_888), verified: false)]
    XCTAssertEqual(MikshatSubscriptionEntitlement.activeExpiration(in: transactions,
                                                                  productID: productID, at: now), renewal)
    XCTAssertNil(MikshatSubscriptionEntitlement.activeExpiration(in: transactions,
                                                                productID: productID, at: renewal))
  }

  func testEmptyEntitlementSnapshotDoesNotGrantAccess() {
    XCTAssertNil(MikshatSubscriptionEntitlement.activeExpiration(in: [], productID: productID, at: now))
  }
}

#if os(Linux)
@main
enum MikshatSubscriptionEntitlementTestRunner {
  static func main() {
    XCTMain([testCase([
      ("verified annual offline entitlement", MikshatSubscriptionEntitlementTests.testVerifiedUnexpiredAnnualTransactionGrantsAccessWithoutAStorefrontProduct),
      ("unverified transaction", MikshatSubscriptionEntitlementTests.testUnverifiedTransactionNeverGrantsAccess),
      ("unrelated product", MikshatSubscriptionEntitlementTests.testAnotherProductCannotUnlockMembership),
      ("expiration boundary", MikshatSubscriptionEntitlementTests.testExpiredAndExactExpirationDateDoNotGrantAccess),
      ("time passage", MikshatSubscriptionEntitlementTests.testPreviouslyVerifiedEntitlementIsReevaluatedWhenTimePasses),
      ("revocation", MikshatSubscriptionEntitlementTests.testRefundOrRevocationImmediatelyRemovesAccess),
      ("replaced upgrade", MikshatSubscriptionEntitlementTests.testReplacedUpgradeTransactionDoesNotGrantAccess),
      ("product type", MikshatSubscriptionEntitlementTests.testOtherProductTypesCannotGrantAnnualSubscriptionAccess),
      ("missing expiration", MikshatSubscriptionEntitlementTests.testTransactionWithoutAnExpirationCannotGrantAnnualAccess),
      ("multiple renewals", MikshatSubscriptionEntitlementTests.testLatestValidRenewalWinsOverExpiredRevokedAndForeignTransactions),
      ("empty snapshot", MikshatSubscriptionEntitlementTests.testEmptyEntitlementSnapshotDoesNotGrantAccess),
    ])])
  }
}
#endif
