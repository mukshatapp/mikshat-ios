import CoreLocation
@testable import Organic_Maps__Debug_
import XCTest

final class CarPlaySharedGuidanceTests: XCTestCase {
  private let destination = CLLocationCoordinate2D(latitude: 25.1, longitude: 45.2)

  func testCarPlayInterfaceUsesRequestedLanguage() {
    let arguments = ProcessInfo.processInfo.arguments
    let observed = String((Bundle.main.preferredLocalizations.first ?? "").prefix(2))
    XCTAssertTrue(["ar", "en"].contains(observed))
    if let index = arguments.firstIndex(of: "-MikshatCarPlayTestLanguage") {
      XCTAssertLessThan(index + 1, arguments.count)
      guard index + 1 < arguments.count else { return }
      XCTAssertEqual(observed, arguments[index + 1])
    }
    XCTAssertEqual(L("mikshat_carplay_gps"), observed == "ar" ? "موقعي" : "My location")
    XCTAssertEqual(L("mikshat_carplay_north_up"), observed == "ar" ? "الشمال أعلى الشاشة" : "North up")
    XCTAssertEqual(L("mikshat_carplay_heading_up"), observed == "ar" ? "اتجاه السير أعلى الشاشة" : "Heading up")
  }

  func testInactiveStateRemainsUnchanged() {
    var state = CarPlaySharedGuidanceState()
    XCTAssertNil(state.current)
    XCTAssertEqual(state.update(nil), .unchanged)
    XCTAssertNil(state.current)
  }

  func testSharedJourneyLifecyclePreservesDirectMode() throws {
    var state = CarPlaySharedGuidanceState()
    let direct = try XCTUnwrap(CarPlayGuidanceIdentity(kind: .direct, coordinate: destination))
    let vehicle = try XCTUnwrap(CarPlayGuidanceIdentity(kind: .vehicle, coordinate: destination))

    XCTAssertEqual(state.update(direct), .started)
    XCTAssertEqual(state.current, direct)
    XCTAssertEqual(state.current?.kind, .direct)
    XCTAssertEqual(state.update(direct), .unchanged)
    XCTAssertEqual(state.current?.kind, .direct)
    XCTAssertEqual(state.update(vehicle), .changed)
    XCTAssertEqual(state.current?.kind, .vehicle)
    XCTAssertEqual(state.update(nil), .ended)
    XCTAssertNil(state.current)
    XCTAssertEqual(state.update(nil), .unchanged)
  }

  func testRepeatedSnapshotsDoNotStartAnotherSession() throws {
    var state = CarPlaySharedGuidanceState()
    let direct = try XCTUnwrap(CarPlayGuidanceIdentity(kind: .direct, coordinate: destination))
    XCTAssertEqual(state.update(direct), .started)
    for _ in 0..<20 {
      let sameDestination = CarPlayGuidanceIdentity(kind: .direct, coordinate: destination)
      XCTAssertEqual(state.update(sameDestination), .unchanged)
      XCTAssertEqual(state.current, direct)
    }
  }

  func testDestinationChangeStartsAChangedJourneyWithoutEndingIt() throws {
    var state = CarPlaySharedGuidanceState()
    let first = try XCTUnwrap(CarPlayGuidanceIdentity(kind: .direct, coordinate: destination))
    let nextLatitude = try XCTUnwrap(CarPlayGuidanceIdentity(kind: .direct,
                                                            coordinate: CLLocationCoordinate2D(latitude: 25.3, longitude: 45.2)))
    let nextLongitude = try XCTUnwrap(CarPlayGuidanceIdentity(kind: .direct,
                                                             coordinate: CLLocationCoordinate2D(latitude: 25.3, longitude: 45.4)))
    XCTAssertEqual(state.update(first), .started)
    XCTAssertEqual(state.update(nextLatitude), .changed)
    XCTAssertEqual(state.current, nextLatitude)
    XCTAssertEqual(state.update(nextLongitude), .changed)
    XCTAssertEqual(state.current, nextLongitude)
  }

  func testVehicleAndDirectAtTheSameDestinationAreDifferentIdentities() throws {
    let direct = try XCTUnwrap(CarPlayGuidanceIdentity(kind: .direct, coordinate: destination))
    let vehicle = try XCTUnwrap(CarPlayGuidanceIdentity(kind: .vehicle, coordinate: destination))
    XCTAssertNotEqual(direct, vehicle)
    var state = CarPlaySharedGuidanceState()
    XCTAssertEqual(state.update(vehicle), .started)
    XCTAssertEqual(state.update(direct), .changed)
    XCTAssertEqual(state.current?.kind, .direct)
  }

  func testDisconnectResetAllowsOneFreshSessionOnReconnect() throws {
    var state = CarPlaySharedGuidanceState()
    let direct = try XCTUnwrap(CarPlayGuidanceIdentity(kind: .direct, coordinate: destination))
    XCTAssertEqual(state.update(direct), .started)
    state.reset()
    XCTAssertNil(state.current)
    XCTAssertEqual(state.update(nil), .unchanged)
    XCTAssertEqual(state.update(direct), .started)
    XCTAssertEqual(state.update(direct), .unchanged)
    XCTAssertEqual(state.current, direct)
  }

  func testInvalidCoordinatesCannotBecomeGuidanceIdentities() {
    let invalidCoordinates = [
      CLLocationCoordinate2D(latitude: 91, longitude: 45),
      CLLocationCoordinate2D(latitude: -91, longitude: 45),
      CLLocationCoordinate2D(latitude: 25, longitude: 181),
      CLLocationCoordinate2D(latitude: 25, longitude: -181),
      CLLocationCoordinate2D(latitude: .nan, longitude: 45),
      CLLocationCoordinate2D(latitude: 25, longitude: .infinity),
    ]
    for coordinate in invalidCoordinates {
      XCTAssertNil(CarPlayGuidanceIdentity(kind: .direct, coordinate: coordinate))
      XCTAssertNil(CarPlayGuidanceIdentity(kind: .vehicle, coordinate: coordinate))
    }
    XCTAssertNotNil(CarPlayGuidanceIdentity(kind: .direct,
                                          coordinate: CLLocationCoordinate2D(latitude: 90, longitude: 180)))
    XCTAssertNotNil(CarPlayGuidanceIdentity(kind: .vehicle,
                                          coordinate: CLLocationCoordinate2D(latitude: -90, longitude: -180)))
  }
}
