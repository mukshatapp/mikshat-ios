@testable import Organic_Maps__Debug_
import XCTest
import UIKit
import CoreLocation
import Darwin

final class MikshatMemoryDiagnosticsTests: XCTestCase {
  func test_SnapshotReadsCurrentProcessFootprintAndResidentMemory() throws {
    let snapshot = MikshatMemoryDiagnostics.Snapshot.capture()
    XCTAssertNil(snapshot.error)
    XCTAssertGreaterThan(try XCTUnwrap(snapshot.physicalFootprintBytes), 0)
    XCTAssertGreaterThan(try XCTUnwrap(snapshot.residentBytes), 0)
    XCTAssertTrue(snapshot.logFields.contains("phys_footprint_bytes="))
    XCTAssertTrue(snapshot.logFields.contains("resident_bytes="))
  }

  func test_FailedSampleDoesNotReportZeroMemoryAsAValidMeasurement() {
    let snapshot = MikshatMemoryDiagnostics.Snapshot(physicalFootprintBytes: nil,
                                                    residentBytes: nil, availableBytes: nil,
                                                    error: KERN_FAILURE)
    XCTAssertTrue(snapshot.logFields.contains("memory_sample_error="))
    XCTAssertFalse(snapshot.logFields.contains("bytes="))
  }
}

final class MikshatHeadingCacheLifecycleTests: XCTestCase {
  func test_CacheKeepsHeadingUntilTheLastCompassClientEnds() {
    let sensor = MikshatHeadingSensor.shared
    let heading = CLHeading()
    let manager = CLLocationManager()
    sensor.begin()
    sensor.begin()
    sensor.locationManager(manager, didUpdateHeading: heading)
    XCTAssertTrue(MikshatHeadingSensor.cachedHeading === heading)

    sensor.end()
    XCTAssertTrue(MikshatHeadingSensor.cachedHeading === heading)
    sensor.end()
    XCTAssertNil(MikshatHeadingSensor.cachedHeading)
    sensor.locationManager(manager, didUpdateHeading: heading)
    XCTAssertNil(MikshatHeadingSensor.cachedHeading, "Callbacks without a compass client cannot refill the cache")
  }

  func test_PauseRejectsLateHeadingAndFailureClearsResumedCache() {
    let sensor = MikshatHeadingSensor.shared
    let heading = CLHeading()
    let manager = CLLocationManager()
    sensor.begin()
    defer {
      NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
      sensor.end()
    }
    sensor.locationManager(manager, didUpdateHeading: heading)
    XCTAssertTrue(MikshatHeadingSensor.cachedHeading === heading)

    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertNil(MikshatHeadingSensor.cachedHeading)
    sensor.locationManager(manager, didUpdateHeading: heading)
    XCTAssertNil(MikshatHeadingSensor.cachedHeading, "A late callback while suspended must remain unavailable")

    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    sensor.locationManager(manager, didUpdateHeading: heading)
    XCTAssertTrue(MikshatHeadingSensor.cachedHeading === heading)
    sensor.locationManager(manager, didFailWithError: NSError(domain: kCLErrorDomain, code: CLError.headingFailure.rawValue))
    XCTAssertNil(MikshatHeadingSensor.cachedHeading)
  }
}
