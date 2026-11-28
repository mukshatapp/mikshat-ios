import CarPlay
import CoreLocation
@testable import Organic_Maps__Debug_
import XCTest

final class CarPlayRouterSharedSessionTests: XCTestCase {
  private var previousRouterType: MWMRouterType!
  private var router: CarPlayRouter!

  override func setUpWithError() throws {
    try super.setUpWithError()
    let map = try XCTUnwrap(MapViewController.shared())
    map.loadViewIfNeeded()
    previousRouterType = MWMRouter.type()
    MWMRouter.stopRouting()
    MWMRouter.enableAutoAddLastLocation(false)
    MWMRouter.setType(.ruler)
    router = CarPlayRouter()
  }

  override func tearDown() {
    router?.cancelNavigationSession()
    MWMRouter.stopRouting()
    if let previousRouterType {
      MWMRouter.setType(previousRouterType)
    }
    router = nil
    super.tearDown()
  }

  func testRulerPreviewSurvivesConnectingCarPlay() {
    seedEndpoints()

    router.restoreTripPreviewOnCarplay(beforeRootTemplateDidAppear: true)
    router.restoreTripPreviewOnCarplay(beforeRootTemplateDidAppear: false)

    XCTAssertEqual(MWMRouter.type(), .ruler)
    XCTAssertEqual(MWMRouter.points().map(\.title), ["Origin", "Destination"])
    XCTAssertFalse(MWMRouter.isMikshatDirectActive())
    XCTAssertNil(router.previewTrip)
  }

  func testRulerDestinationWithoutOriginSurvivesConnectingCarPlay() {
    MWMRouter.addPoint(point(type: .finish, title: "Destination", coordinate: 13))

    router.restoreTripPreviewOnCarplay(beforeRootTemplateDidAppear: true)

    XCTAssertEqual(MWMRouter.type(), .ruler)
    XCTAssertEqual(MWMRouter.points().map(\.title), ["Destination"])
    XCTAssertNil(MWMRouter.startPoint())
    XCTAssertNil(router.restoredDirectTrip())
  }

  func testActiveDirectTripRestoresWithoutBuildingAVehicleRoute() throws {
    try startCoreDirectTrip()
    let originalPoints = MWMRouter.points().map(\.title)

    let trip = try XCTUnwrap(router.restoredDirectTrip())
    router.restoreTripPreviewOnCarplay(beforeRootTemplateDidAppear: false)

    XCTAssertEqual(MWMRouter.type(), .ruler)
    XCTAssertTrue(MWMRouter.isMikshatDirectActive())
    XCTAssertEqual(MWMRouter.points().map(\.title), originalPoints)
    XCTAssertTrue(router.matchesCurrentDestination(trip, routeType: .ruler))
    XCTAssertFalse(router.matchesCurrentDestination(trip, routeType: .vehicle))
    XCTAssertNil(trip.routeChoices.first?.userInfo)
  }

  func testVehicleRestorationDoesNotConsumeActiveDirectGuidance() throws {
    try startCoreDirectTrip()

    XCTAssertNil(router.restoredNavigationSession())

    XCTAssertTrue(MWMRouter.isMikshatDirectActive())
    XCTAssertEqual(MWMRouter.type(), .ruler)
    XCTAssertEqual(MWMRouter.pointsCount(), 2)
    XCTAssertEqual(MWMRouter.finishPoint()?.title, "Destination")
  }

  func testEndingRulerPreviewDoesNotChangeTheSelectedRouter() {
    seedEndpoints()

    router.completeRouteAndRemovePoints()

    XCTAssertEqual(MWMRouter.type(), .ruler)
    XCTAssertEqual(MWMRouter.pointsCount(), 0)
  }

  func testStaleVehicleRecoveryDoesNotReplaceDirectGuidance() throws {
    try startCoreDirectTrip()
    let trip = try XCTUnwrap(router.restoredDirectTrip())

    router.updateStartPointAndRebuild(trip: trip)
    router.startRoute()

    XCTAssertTrue(MWMRouter.isMikshatDirectActive())
    XCTAssertEqual(MWMRouter.type(), .ruler)
    XCTAssertTrue(router.matchesCurrentDestination(trip, routeType: .ruler))
  }

  func testEndingRestoredDirectTripClearsCoreDirectStateWithoutAPhoneHUD() throws {
    try startCoreDirectTrip()
    XCTAssertNil(MikshatNavigationCoordinator.directView)

    router.cancelTrip()

    XCTAssertFalse(MWMRouter.isMikshatDirectActive())
    XCTAssertEqual(MWMRouter.type(), .ruler)
    XCTAssertEqual(MWMRouter.pointsCount(), 0)
    XCTAssertNil(router.previewTrip)
  }

  func testChangedPhoneDestinationDoesNotMatchThePreviousCarPlayTrip() throws {
    MWMRouter.setType(.vehicle)
    seedEndpoints()
    let trip = try XCTUnwrap(currentTrip())
    XCTAssertTrue(router.matchesCurrentDestination(trip, routeType: .vehicle))

    MWMRouter.addPoint(point(type: .finish, title: "New destination", coordinate: 14))

    XCTAssertFalse(router.matchesCurrentDestination(trip, routeType: .vehicle))
  }

  func testOldTripDoesNotReceiveBuildErrorsForTheNewPhoneDestination() throws {
    MWMRouter.setType(.vehicle)
    seedEndpoints()
    router.previewTrip = try XCTUnwrap(currentTrip())
    let listener = SharedSessionRouterListener()
    router.addListener(listener)
    router.setRoutingPresentationActive(true)
    MWMRouter.addPoint(point(type: .finish, title: "New destination", coordinate: 14))

    router.processRouteBuilderEvent(with: .internalError, countries: [])
    router.didLocationUpdate([])

    XCTAssertEqual(listener.eventCount, 0)
  }

  func testDirectGuidanceDoesNotReceiveVehicleBuildErrors() throws {
    try startCoreDirectTrip()
    router.previewTrip = try XCTUnwrap(router.restoredDirectTrip())
    let listener = SharedSessionRouterListener()
    router.addListener(listener)
    router.setRoutingPresentationActive(true)

    router.processRouteBuilderEvent(with: .internalError, countries: [])
    router.didLocationUpdate([])

    XCTAssertEqual(listener.eventCount, 0)
    XCTAssertTrue(MWMRouter.isMikshatDirectActive())
    XCTAssertEqual(MWMRouter.type(), .ruler)
  }

  private func seedEndpoints() {
    MWMRouter.addPoint(point(type: .start, title: "Origin", coordinate: 10))
    MWMRouter.addPoint(point(type: .finish, title: "Destination", coordinate: 13))
  }

  private func startCoreDirectTrip() throws {
    seedEndpoints()
    let start = try XCTUnwrap(MWMRouter.startPoint())
    let end = try XCTUnwrap(MWMRouter.finishPoint())
    MWMRouter.beginMikshatDirect(from: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude),
                                to: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude))
    XCTAssertTrue(MWMRouter.isMikshatDirectActive())
  }

  private func currentTrip() -> CPTrip? {
    guard let start = MWMRouter.startPoint(), let end = MWMRouter.finishPoint() else { return nil }
    return router.createTrip(startPoint: start, endPoint: end)
  }

  private func point(type: MWMRoutePointType, title: String, coordinate: Double) -> MWMRoutePoint {
    MWMRoutePoint(cgPoint: CGPoint(x: coordinate, y: coordinate), title: title,
                  subtitle: nil, type: type, intermediateIndex: 0)
  }
}

private final class SharedSessionRouterListener: CarPlayRouterListener {
  private(set) var eventCount = 0

  func didCreateRoute(routeInfo: RouteInfo, trip: CPTrip) { eventCount += 1 }
  func didUpdateRouteInfo(_ routeInfo: RouteInfo, forTrip trip: CPTrip) { eventCount += 1 }
  func didFailureBuildRoute(forTrip trip: CPTrip, code: RouterResultCode, countries: [String]) { eventCount += 1 }
  func routeDidFinish(_ trip: CPTrip) { eventCount += 1 }
}
