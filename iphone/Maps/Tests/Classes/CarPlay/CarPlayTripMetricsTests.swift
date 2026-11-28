import CoreLocation
@testable import Organic_Maps__Debug_
import XCTest

final class CarPlayTripMetricsTests: XCTestCase {
  private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
  private let coordinate = CLLocationCoordinate2D(latitude: 25, longitude: 45)
  private let destination = CLLocationCoordinate2D(latitude: 25.1, longitude: 45)

  func testVehicleUsesRoutingDistanceAndDurationWhileStopped() throws {
    var metrics = CarPlayTripMetrics()
    let result = metrics.update(location: location(speed: 0), directDestination: nil,
                                routeDistance: 21_500, routeDuration: 1_800, now: epoch)
    XCTAssertEqual(result.speedMetersPerSecond, 0)
    XCTAssertEqual(result.distanceMeters, 21_500)
    XCTAssertEqual(result.remainingTime, 1_800)
    XCTAssertEqual(try XCTUnwrap(result.arrivalDate), epoch.addingTimeInterval(1_800))
  }

  func testDirectDistanceIsGeographicAndDoesNotUseVehicleEstimates() throws {
    var metrics = CarPlayTripMetrics()
    let result = metrics.update(location: location(speed: 10), directDestination: destination,
                                routeDistance: 999_999, routeDuration: 999_999, now: epoch)
    XCTAssertEqual(try XCTUnwrap(result.distanceMeters), 11_080, accuracy: 100)
    XCTAssertNil(result.remainingTime)
    XCTAssertNil(result.arrivalDate)
  }

  func testDirectETARequiresDistinctFixesAndUsesSmoothedSpeed() throws {
    var metrics = CarPlayTripMetrics()
    for speed in [8.0, 10.0] {
      let time = epoch.addingTimeInterval(speed == 8 ? 0 : 1)
      let result = metrics.update(location: location(speed: speed, timestamp: time), directDestination: destination,
                                  routeDistance: nil, routeDuration: nil, now: time)
      XCTAssertNil(result.remainingTime)
    }
    let time = epoch.addingTimeInterval(2)
    let result = metrics.update(location: location(speed: 12, timestamp: time), directDestination: destination,
                                routeDistance: nil, routeDuration: nil, now: time)
    XCTAssertEqual(result.speedMetersPerSecond, 12)
    XCTAssertEqual(try XCTUnwrap(result.remainingTime), try XCTUnwrap(result.distanceMeters) / 10, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(result.arrivalDate).timeIntervalSince(time), try XCTUnwrap(result.remainingTime), accuracy: 0.001)
  }

  func testRepeatedTimerReadsCannotWarmUpETA() {
    var metrics = CarPlayTripMetrics()
    let fix = location(speed: 10)
    for offset in 0...5 {
      let result = metrics.update(location: fix, directDestination: destination, routeDistance: nil,
                                  routeDuration: nil, now: epoch.addingTimeInterval(Double(offset)))
      XCTAssertNil(result.remainingTime)
    }
  }

  func testStoppedDirectGuidanceDropsETAAndKeepsDistance() throws {
    var metrics = warmedMetrics()
    let time = epoch.addingTimeInterval(3)
    let result = metrics.update(location: location(speed: 0, timestamp: time), directDestination: destination,
                                routeDistance: nil, routeDuration: nil, now: time)
    XCTAssertEqual(result.speedMetersPerSecond, 0)
    XCTAssertNotNil(result.distanceMeters)
    XCTAssertNil(result.remainingTime)
    XCTAssertNil(result.arrivalDate)
    let resumed = epoch.addingTimeInterval(4)
    XCTAssertNil(metrics.update(location: location(speed: 10, timestamp: resumed), directDestination: destination,
                                routeDistance: nil, routeDuration: nil, now: resumed).remainingTime)
  }

  func testStaleOrMissingFixDoesNotDisplayCachedVehicleMetrics() {
    for fix in [location(speed: 10), nil] {
      var metrics = CarPlayTripMetrics()
      let result = metrics.update(location: fix, directDestination: nil, routeDistance: 500,
                                  routeDuration: 60, now: epoch.addingTimeInterval(11))
      assertEmpty(result)
    }
  }

  func testPoorAccuracyInvalidCoordinateAndFutureFixAreRejected() {
    let badFixes = [
      location(speed: 10, accuracy: -1),
      location(speed: 10, accuracy: 101),
      location(speed: 10, accuracy: .infinity),
      location(speed: 10, coordinate: CLLocationCoordinate2D(latitude: 91, longitude: 45)),
      location(speed: 10, timestamp: epoch.addingTimeInterval(2)),
    ]
    for fix in badFixes {
      var metrics = CarPlayTripMetrics()
      assertEmpty(metrics.update(location: fix, directDestination: destination, routeDistance: nil,
                                  routeDuration: nil, now: epoch))
    }
  }

  func testUnknownOrNonfiniteSpeedKeepsValidDirectDistanceWithoutETA() {
    for speed in [-1, Double.nan, Double.infinity] {
      var metrics = warmedMetrics()
      let time = epoch.addingTimeInterval(3)
      let result = metrics.update(location: location(speed: speed, timestamp: time), directDestination: destination,
                                  routeDistance: nil, routeDuration: nil, now: time)
      XCTAssertNil(result.speedMetersPerSecond)
      XCTAssertNotNil(result.distanceMeters)
      XCTAssertNil(result.remainingTime)
    }
  }

  func testDestinationChangeAndResetRequireNewSpeedHistory() {
    var metrics = warmedMetrics()
    let time = epoch.addingTimeInterval(3)
    let otherDestination = CLLocationCoordinate2D(latitude: 25.2, longitude: 45)
    let result = metrics.update(location: location(speed: 10, timestamp: time), directDestination: otherDestination,
                                routeDistance: nil, routeDuration: nil, now: time)
    XCTAssertNil(result.remainingTime)
    XCTAssertNotNil(result.distanceMeters)
    metrics = warmedMetrics()
    metrics.reset()
    XCTAssertNil(metrics.update(location: location(speed: 10, timestamp: time), directDestination: destination,
                                routeDistance: nil, routeDuration: nil, now: time).remainingTime)
  }

  func testInvalidDirectDestinationCannotFallBackToVehicleMetrics() {
    var metrics = warmedMetrics()
    let time = epoch.addingTimeInterval(3)
    let result = metrics.update(location: location(speed: 10, timestamp: time),
                                directDestination: CLLocationCoordinate2D(latitude: .nan, longitude: 45),
                                routeDistance: 500, routeDuration: 60, now: time)
    XCTAssertEqual(result.speedMetersPerSecond, 10)
    XCTAssertNil(result.distanceMeters)
    XCTAssertNil(result.remainingTime)
  }

  func testInvalidVehicleValuesDoNotProduceArrivalEstimates() {
    for values in [(Double.nan, 60.0), (-1.0, 60.0), (500.0, Double.infinity), (500.0, -1.0), (500.0, 0.0)] {
      var metrics = CarPlayTripMetrics()
      let result = metrics.update(location: location(speed: 10), directDestination: nil,
                                  routeDistance: values.0, routeDuration: values.1, now: epoch)
      XCTAssertNil(result.remainingTime)
      XCTAssertNil(result.arrivalDate)
    }
  }

  func testOutOfOrderFixCannotReplaceLiveMetrics() {
    var metrics = warmedMetrics()
    assertEmpty(metrics.update(location: location(speed: 10, timestamp: epoch.addingTimeInterval(1)),
                                directDestination: destination, routeDistance: nil, routeDuration: nil,
                                now: epoch.addingTimeInterval(3)))
  }

  func testUnreasonablyLongDirectETAIsUnavailable() {
    var metrics = CarPlayTripMetrics()
    let distant = CLLocationCoordinate2D(latitude: -25, longitude: -135)
    for offset in 0...2 {
      let time = epoch.addingTimeInterval(Double(offset))
      let result = metrics.update(location: location(speed: 1, timestamp: time), directDestination: distant,
                                  routeDistance: nil, routeDuration: nil, now: time)
      XCTAssertNotNil(result.distanceMeters)
      XCTAssertNil(result.remainingTime)
      XCTAssertNil(result.arrivalDate)
    }
  }

  private func location(speed: CLLocationSpeed,
                        accuracy: CLLocationAccuracy = 5,
                        timestamp: Date? = nil,
                        coordinate: CLLocationCoordinate2D? = nil) -> CLLocation {
    CLLocation(coordinate: coordinate ?? self.coordinate, altitude: 0,
               horizontalAccuracy: accuracy, verticalAccuracy: 5, course: 0,
               speed: speed, timestamp: timestamp ?? epoch)
  }

  private func warmedMetrics() -> CarPlayTripMetrics {
    var metrics = CarPlayTripMetrics()
    for offset in 0...2 {
      let time = epoch.addingTimeInterval(Double(offset))
      _ = metrics.update(location: location(speed: 10, timestamp: time), directDestination: destination,
                          routeDistance: nil, routeDuration: nil, now: time)
    }
    return metrics
  }

  private func assertEmpty(_ snapshot: CarPlayTripMetrics.Snapshot, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNil(snapshot.speedMetersPerSecond, file: file, line: line)
    XCTAssertNil(snapshot.distanceMeters, file: file, line: line)
    XCTAssertNil(snapshot.remainingTime, file: file, line: line)
    XCTAssertNil(snapshot.arrivalDate, file: file, line: line)
  }
}
