@testable import Organic_Maps__Debug_
import XCTest
import UIKit
import CoreLocation

final class SearchOnMapHeaderViewTests: XCTestCase {
  private var header: SearchOnMapHeaderView!
  private var searchBar: UISearchBar!
  private var actions: UIStackView!

  override func setUpWithError() throws {
    try super.setUpWithError()
    header = SearchOnMapHeaderView(frame: CGRect(x: 0, y: 0, width: 400, height: 60))
    searchBar = try XCTUnwrap(header.subviews.compactMap { $0 as? UISearchBar }.first)
    actions = try XCTUnwrap(header.subviews.compactMap { $0 as? UIStackView }.first)
  }

  override func tearDown() {
    header = nil
    searchBar = nil
    actions = nil
    super.tearDown()
  }

  func test_GivenRoutePointActions_WhenTypingAndClearing_ThenVisibilityFollowsActualText() {
    header.setRoutePointActions(.init(title: "Choose destination", canSelectCurrentLocation: true))
    assertActionsHidden(false)

    searchBar.text = "cafe"
    searchBar.searchTextField.sendActions(for: .editingChanged)
    assertActionsHidden(true)

    searchBar.text = ""
    searchBar.searchTextField.sendActions(for: .editingChanged)
    assertActionsHidden(false)
  }

  func test_GivenProgrammaticQuery_WhenLocationAvailabilityChanges_ThenActionsStayHiddenUntilCleared() {
    header.setRoutePointActions(.init(title: "Choose destination", canSelectCurrentLocation: true))
    header.setSearchText("cafe")
    assertActionsHidden(true)

    header.setRoutePointActions(.init(title: "Choose destination", canSelectCurrentLocation: false))
    assertActionsHidden(true)
    XCTAssertEqual(header.searchQuery.text, "cafe")

    header.setSearchText("")
    assertActionsHidden(false)
    XCTAssertTrue(actions.arrangedSubviews[0].isHidden)
    XCTAssertFalse(actions.arrangedSubviews[1].isHidden)
  }

  func test_GivenOrdinarySearch_WhenQueryIsCleared_ThenRoutePointActionsStayHidden() {
    header.setRoutePointActions(nil)
    header.setSearchText("cafe")
    header.setSearchText("")

    assertActionsHidden(true)
  }

  func test_CoordinateInputCreatesBothRowsWithActiveFieldWidthConstraints() {
    let input = MikshatCoordinateInputView()
    let rows = input.arrangedSubviews.compactMap { $0 as? UIStackView }
    XCTAssertEqual(rows.count, 2)
    for row in rows {
      let fields = row.arrangedSubviews.compactMap { $0 as? UITextField }
      XCTAssertEqual(fields.count, 2)
      XCTAssertTrue(row.constraints.contains { constraint in
        constraint.isActive && constraint.firstItem === fields[0]
          && constraint.secondItem === fields[1] && constraint.multiplier == 0.65
      })
    }
  }

  func test_KeyboardRequestCancelledBeforeAttachmentDoesNotBecomeFirstResponder() {
    header.setIsSearching(true)
    header.setIsSearching(true)
    header.setIsSearching(false)
    let finished = expectation(description: "Pending focus request processed")
    DispatchQueue.main.async {
      XCTAssertFalse(self.searchBar.isFirstResponder)
      finished.fulfill()
    }
    wait(for: [finished], timeout: 2)
  }

  private func assertActionsHidden(_ hidden: Bool, file: StaticString = #filePath, line: UInt = #line) {
    let settled = XCTNSPredicateExpectation(predicate: NSPredicate { [actions] _, _ in
      actions?.isHidden == hidden && actions?.alpha == (hidden ? 0 : 1)
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 2), .completed, file: file, line: line)
  }
}

final class MikshatHeadingSettingsTests: XCTestCase {
  func test_TransparencyDefaultsAndClamping() {
    let defaults = UserDefaults.standard
    let keys = ["mikshat_compass_transparency_enabled", "mikshat_compass_transparency"]
    let saved = keys.map { defaults.object(forKey: $0) }
    defer {
      for (key, value) in zip(keys, saved) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
      }
    }
    keys.forEach { defaults.removeObject(forKey: $0) }
    XCTAssertFalse(MikshatCompassAppearance.enabled)
    XCTAssertEqual(MikshatCompassAppearance.percentage, 40)
    defaults.set(120, forKey: keys[1])
    XCTAssertEqual(MikshatCompassAppearance.percentage, 100)
    defaults.set(-20, forKey: keys[1])
    XCTAssertEqual(MikshatCompassAppearance.percentage, 0)
  }

  func test_HeadingScreenSupportsAppNavigationAndDisplaysAllModes() {
    let controller = SettingsBuilder.build(.mikshatTools)
    XCTAssertTrue(controller is MWMTableViewController)
    let tableController = controller as! MikshatToolsViewController
    XCTAssertTrue(tableController.hasNavigationBar)
    tableController.loadViewIfNeeded()
    XCTAssertEqual(tableController.tableView(tableController.tableView, numberOfRowsInSection: 0), 3)
  }
}

final class SearchOnMapManagerTests: XCTestCase {
  @available(iOS 16.0, *)
  func test_GivenInitialLandscapeSearch_WhenAttached_ThenTabContentHasNoExtraLeadingInset() throws {
    let mapViewController = try XCTUnwrap(MapViewController.shared())
    mapViewController.loadViewIfNeeded()
    let scene = try XCTUnwrap(mapViewController.view.window?.windowScene)
    scene.requestGeometryUpdate(UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscapeLeft)) { error in
      XCTFail("Could not rotate scene: \(error)")
    }
    let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      scene.interfaceOrientation.isLandscape
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
    defer {
      scene.requestGeometryUpdate(UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait))
      let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        scene.interfaceOrientation.isPortrait
      }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
    }

    let expectedLeadingInset = mapViewController.view.safeAreaInsets.left
    guard expectedLeadingInset > 0 else {
      throw XCTSkip("This device has no leading safe area inset in landscape")
    }
    let manager = SearchOnMapManager()
    manager.startSearching(isRouting: false)
    let searchController = try XCTUnwrap(manager.viewController)
    defer {
      manager.close()
      waitUntilDetached(searchController)
    }
    searchController.view.layoutIfNeeded()
    let tabs = try XCTUnwrap(searchController.children.compactMap { $0 as? SearchTabViewController }.first)
    let contentCollection = try XCTUnwrap(tabs.view.subviews.compactMap { $0 as? UICollectionView }.first)
    XCTAssertEqual(searchController.view.safeAreaInsets.left, expectedLeadingInset, accuracy: 1)
    XCTAssertEqual(searchController.availableAreaView.frame.minX,
                   searchController.view.safeAreaInsets.left, accuracy: 1)
    XCTAssertEqual(tabs.view.safeAreaInsets.left, 0, accuracy: 1)
    XCTAssertEqual(contentCollection.adjustedContentInset.left, 0, accuracy: 1)
  }

  func test_GivenSearchModes_WhenStartedRepeatedly_ThenReusesOnlyMatchingMode() throws {
    let previousSearchMode = Search.searchMode()
    defer { Search.setSearchMode(previousSearchMode) }
    let mapViewController = try XCTUnwrap(MapViewController.shared())
    mapViewController.loadViewIfNeeded()
    let navigationManager = MWMNavigationDashboardManager.shared()
    let routePreviewDelegate = try XCTUnwrap(navigationManager as? MWMRoutePreviewDelegate)
    let manager = SearchOnMapManager()
    var controllers: [SearchOnMapViewController] = []
    defer {
      navigationManager.cancelRoutePointSelection()
      manager.close()
      controllers.forEach(waitUntilDetached)
    }

    manager.startSearching(isRouting: false)
    let normalController = try XCTUnwrap(manager.viewController)
    controllers.append(normalController)
    manager.startSearching(isRouting: false)
    XCTAssertTrue(manager.viewController === normalController)

    routePreviewDelegate.routePreviewDidSelect(
      MWMRoutePointSelection(point: nil, type: .finish, shouldAppend: false)
    )
    manager.startSearching(isRouting: true)
    let routePointController = try XCTUnwrap(manager.viewController)
    controllers.append(routePointController)
    XCTAssertFalse(routePointController === normalController)
    manager.startSearching(isRouting: true)
    XCTAssertTrue(manager.viewController === routePointController)

    navigationManager.cancelRoutePointSelection()
    manager.startSearching(isRouting: true)
    let routingController = try XCTUnwrap(manager.viewController)
    controllers.append(routingController)
    XCTAssertFalse(routingController === routePointController)
    manager.startSearching(isRouting: true)
    XCTAssertTrue(manager.viewController === routingController)

    waitUntilDetached(normalController)
    waitUntilDetached(routePointController)
    XCTAssertTrue(manager.viewController === routingController)
  }

  func test_GivenClosingSearch_WhenReopenedBeforeAnimationEnds_ThenCreatesANewController() throws {
    let previousSearchMode = Search.searchMode()
    defer { Search.setSearchMode(previousSearchMode) }
    let mapViewController = try XCTUnwrap(MapViewController.shared())
    mapViewController.loadViewIfNeeded()
    let manager = SearchOnMapManager()
    let observer = SearchClosureObserver(manager: manager)
    manager.addObserver(observer)
    manager.startSearching(isRouting: false)
    let closingController = try XCTUnwrap(manager.viewController)

    manager.close()

    XCTAssertFalse(manager.isSearching)
    XCTAssertEqual(observer.wasSearchingWhenClosed, false)
    manager.startSearching(isRouting: false)
    let reopenedController = try XCTUnwrap(manager.viewController)
    defer {
      manager.close()
      waitUntilDetached(reopenedController)
    }
    XCTAssertFalse(closingController === reopenedController)

    waitUntilDetached(closingController)
    XCTAssertTrue(manager.viewController === reopenedController)
    XCTAssertTrue(reopenedController.parent === mapViewController)
  }

  func test_GivenRoutePointSearch_WhenRouteStopsExternally_ThenClosesPickerAndSearch() throws {
    let mapViewController = try XCTUnwrap(MapViewController.shared())
    mapViewController.loadViewIfNeeded()
    let manager = mapViewController.searchManager
    let navigationManager = MWMNavigationDashboardManager.shared()
    let routePreviewDelegate = try XCTUnwrap(navigationManager as? MWMRoutePreviewDelegate)
    routePreviewDelegate.routePreviewDidSelect(
      MWMRoutePointSelection(point: nil, type: .finish, shouldAppend: false)
    )
    manager.startSearching(isRouting: true)
    let searchController = try XCTUnwrap(manager.viewController)
    searchController.interactor?.handle(.chooseOnMapButtonDidTap)
    let picker = try XCTUnwrap(mapViewController.children.compactMap { $0 as? MapPointPickerViewController }.first)

    MWMRouter.stopRouting()

    XCTAssertFalse(navigationManager.isRoutePointSelectionActive)
    XCTAssertFalse(manager.isSearching)
    waitUntilDetached(searchController)
    waitUntilDetached(picker)
  }

  func test_GivenOrdinarySearch_WhenRouteStopsExternally_ThenKeepsSearchOpen() throws {
    let mapViewController = try XCTUnwrap(MapViewController.shared())
    mapViewController.loadViewIfNeeded()
    let manager = mapViewController.searchManager
    manager.startSearching(isRouting: false)
    let searchController = try XCTUnwrap(manager.viewController)
    defer {
      manager.close()
      waitUntilDetached(searchController)
    }

    MWMRouter.stopRouting()

    XCTAssertTrue(manager.viewController === searchController)
  }

  private func waitUntilDetached(_ controller: UIViewController) {
    let detached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      controller.parent == nil
    }, object: nil)
    wait(for: [detached], timeout: 3)
  }
}

final class MapPointPickerViewControllerTests: XCTestCase {
  func test_GivenVisibleMapControls_WhenPickerIsPresentedAndClosed_ThenKeepsControlsVisible() throws {
    let mapViewController = try XCTUnwrap(MapViewController.shared())
    mapViewController.loadViewIfNeeded()
    let controlsManager = try XCTUnwrap(MWMMapViewControlsManager.manager())
    let previousHidden = controlsManager.hidden
    let previousSideButtonsHidden = controlsManager.sideButtonsHidden
    let previousZoomHidden = controlsManager.zoomHidden
    controlsManager.hidden = false
    controlsManager.sideButtonsHidden = false
    controlsManager.zoomHidden = false
    defer {
      controlsManager.hidden = previousHidden
      controlsManager.sideButtonsHidden = previousSideButtonsHidden
      controlsManager.zoomHidden = previousZoomHidden
    }
    let picker = MapPointPickerViewController(title: "Choose point",
                                              hint: "Move the map",
                                              enableBounds: false,
                                              initialMercatorPosition: nil,
                                              shouldChangeViewport: false)

    picker.present(in: mapViewController)

    XCTAssertTrue(picker.parent === mapViewController)
    XCTAssertFalse(controlsManager.hidden)
    XCTAssertFalse(controlsManager.sideButtonsHidden)
    XCTAssertFalse(controlsManager.zoomHidden)

    picker.close()
    let detached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      picker.parent == nil
    }, object: nil)
    wait(for: [detached], timeout: 3)
    XCTAssertFalse(controlsManager.hidden)
    XCTAssertFalse(controlsManager.sideButtonsHidden)
    XCTAssertFalse(controlsManager.zoomHidden)
  }

  func test_GivenButtonDismissalInProgress_WhenClosedExternally_ThenDoesNotDeliverResult() throws {
    let mapViewController = try XCTUnwrap(MapViewController.shared())
    mapViewController.loadViewIfNeeded()
    let picker = MapPointPickerViewController(title: "Choose point",
                                              hint: "Move the map",
                                              enableBounds: false,
                                              initialMercatorPosition: nil,
                                              shouldChangeViewport: false)
    var didCancel = false
    picker.cancelHandler = { didCancel = true }
    picker.present(in: mapViewController)
    let cancelButton = try XCTUnwrap(picker.view.firstDescendant {
      ($0 as? UIButton)?.title(for: .normal) == L("cancel")
    } as? UIButton)

    cancelButton.sendActions(for: .touchUpInside)
    picker.close()

    let detached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      picker.parent == nil
    }, object: nil)
    wait(for: [detached], timeout: 3)
    XCTAssertFalse(didCancel)
  }
}

private extension UIView {
  func firstDescendant(where predicate: (UIView) -> Bool) -> UIView? {
    for subview in subviews {
      if predicate(subview) {
        return subview
      }
      if let descendant = subview.firstDescendant(where: predicate) {
        return descendant
      }
    }
    return nil
  }
}

private final class SearchClosureObserver: NSObject, SearchOnMapManagerObserver {
  private let manager: SearchOnMapManager
  var wasSearchingWhenClosed: Bool?

  init(manager: SearchOnMapManager) {
    self.manager = manager
  }

  func searchManager(didChangeState state: SearchOnMapState) {
    if state == .closed {
      wasSearchingWhenClosed = manager.isSearching
    }
  }
}


final class MikshatCoordinateEntryTests: XCTestCase {
  func test_CompleteArabicEntryEnablesMapWithoutSubmittingUntilTap() throws {
    let input = MikshatCoordinateInputView()
    let rows = input.arrangedSubviews.compactMap { $0 as? UIStackView }
    let fields = rows.flatMap { $0.arrangedSubviews.compactMap { $0 as? UITextField } }
    XCTAssertEqual(fields.count, 4)
    let button = try XCTUnwrap(input.arrangedSubviews.compactMap { $0 as? UIButton }.first)
    var submissions = 0
    input.onSubmit = { value in
      submissions += 1
      XCTAssertEqual(value.latitude, 24 + 9.321 / 60, accuracy: 0.000001)
      XCTAssertEqual(value.longitude, 47 + 16.709 / 60, accuracy: 0.000001)
    }
    XCTAssertFalse(button.isEnabled)
    for (field, text) in zip(fields, ["٢٤", "٠٩٣٢١", "٠٤٧", "١٦٧٠٩"]) {
      XCTAssertFalse(input.textField(field, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: text))
    }
    XCTAssertEqual(fields.map { $0.text ?? "" }, ["24", "09.321", "047", "16.709"])
    XCTAssertTrue(button.isEnabled)
    XCTAssertEqual(submissions, 0)
    button.sendActions(for: .touchUpInside)
    XCTAssertEqual(submissions, 1)
    _ = input.textField(fields[1], shouldChangeCharactersIn: NSRange(location: 0, length: 6), replacementString: "60000")
    XCTAssertFalse(button.isEnabled)
  }

  func test_DeletingDecimalSeparatorDeletesDigitAndAllowsContinuedEditing() throws {
    let input = MikshatCoordinateInputView()
    let rows = input.arrangedSubviews.compactMap { $0 as? UIStackView }
    let minutes = try XCTUnwrap(rows.first?.arrangedSubviews.compactMap { $0 as? UITextField }.last)
    _ = input.textField(minutes, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "09")
    XCTAssertEqual(minutes.text, "09.")
    _ = input.textField(minutes, shouldChangeCharactersIn: NSRange(location: 2, length: 1), replacementString: "")
    XCTAssertEqual(minutes.text, "0")
  }

  func test_BothCompassScreensLoadWithCurrentLocationSection() {
    for controller in [MikshatCompassViewController(target: nil, name: L("mikshat_heading"), general: true),
                       MikshatCompassViewController(target: CLLocationCoordinate2D(latitude: 24, longitude: 47), name: "Destination")] {
      controller.loadViewIfNeeded()
      XCTAssertNotNil(controller.view.firstDescendant { ($0 as? UILabel)?.text == L("mikshat_current_location") })
    }
  }
}


final class MikshatLocationCardTests: XCTestCase {
  func test_CoordinateRowsHaveTwoUnwrappedLinesAndTextCopyButton() {
    for (index, value) in MikshatNavigationMath.coordinatePairs(latitude: 23.934539, longitude: 47.249).enumerated() {
      var didCopy = false
      let row = MikshatCoordinateRow(text: value, format: ["DD", "DDM", "DMS"][index]) { didCopy = true }
      let labels = row.arrangedSubviews.compactMap { $0 as? UIStackView }.flatMap { $0.arrangedSubviews.compactMap { $0 as? UILabel } }
      XCTAssertEqual(labels.count, 2)
      XCTAssertTrue(labels.allSatisfy { $0.numberOfLines == 1 })
      let copy = row.arrangedSubviews.compactMap { $0 as? UIButton }.first
      XCTAssertEqual(copy?.configuration?.title, L("mikshat_copy"))
      copy?.sendActions(for: .touchUpInside)
      XCTAssertTrue(didCopy)
    }
  }

  func test_ShareMessageContainsBothCoordinatesAndOnlyMikshatLink() {
    let text = MikshatShareContent.message(latitude: 23.934312, longitude: 47.249434, name: "نقطة الخريطة")
    XCTAssertTrue(text.contains("N 23° 56.059′"))
    XCTAssertTrue(text.contains("E 047° 14.966′"))
    XCTAssertTrue(text.contains("https://mukshatapp.github.io/map/"))
    XCTAssertFalse(text.contains("omaps.app"))
  }
}

final class MikshatMapControlLayoutTests: XCTestCase {
  func test_NativeControlsStayBelowQiblaWhenAvailableAreaChanges() throws {
    let map = try XCTUnwrap(MapViewController.shared())
    map.loadViewIfNeeded()
    let home = try XCTUnwrap(map.view.subviews.compactMap { $0 as? MikshatHomeControls }.first)
    let buttons = MWMSideButtons.buttons().view!
    XCTAssertFalse(buttons.superview === home.superview, "Regression covers the actual separate containers")
    defer { MWMSideButtons.updateAvailableArea(map.view.bounds) }
    let heights: [CGFloat] = [map.view.bounds.height, 80, 240, map.view.bounds.height]
    for areaHeight in heights {
      MWMSideButtons.updateAvailableArea(CGRect(x: 0, y: 0, width: map.view.bounds.width, height: areaHeight))
      map.view.setNeedsLayout()
      map.view.layoutIfNeeded()
      map.view.layoutIfNeeded()
      let tools = buttons.convert(buttons.bounds, to: map.view)
      let upperTools = home.convert(home.bounds, to: map.view)
      XCTAssertEqual(tools.minY, upperTools.maxY + 12, accuracy: 1)
      XCTAssertEqual(tools.midX, upperTools.midX, accuracy: 1)
      let nativeButtons = buttons.subviews.compactMap { $0 as? UIButton }.sorted { $0.frame.minY < $1.frame.minY }
      XCTAssertEqual(nativeButtons.count, 3)
      for pair in zip(nativeButtons, nativeButtons.dropFirst()) {
        XCTAssertGreaterThanOrEqual(pair.1.frame.minY, pair.0.frame.maxY + 7)
      }
    }
  }
}

final class MikshatSearchDirectionIndicatorTests: XCTestCase {
  func test_AttachingHistoryArrowsDoesNotStartGPS() {
    let wasStarted = LocationManager.isStarted()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    defer {
      window.subviews.forEach { $0.removeFromSuperview() }
      if wasStarted { LocationManager.start() } else { LocationManager.stop() }
    }
    LocationManager.stop()
    for _ in 0..<12 {
      let arrow = MikshatDirectionIndicator()
      arrow.target = CLLocationCoordinate2D(latitude: 24.7136, longitude: 46.6753)
      window.addSubview(arrow)
    }
    XCTAssertFalse(LocationManager.isStarted(), "History decoration must not start or replay GPS into navigation")
  }

  func test_SharedRefreshDoesNotRetainDetachedHistoryArrows() {
    weak var releasedArrow: MikshatDirectionIndicator?
    autoreleasepool {
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
      let arrow = MikshatDirectionIndicator()
      releasedArrow = arrow
      window.addSubview(arrow)
      arrow.removeFromSuperview()
    }
    XCTAssertNil(releasedArrow)
  }
}

final class SearchTabLayoutRegressionTests: XCTestCase {
  private func collections(in view: UIView) -> [UICollectionView] {
    view.subviews.flatMap { child -> [UICollectionView] in
      if let collection = child as? UICollectionView { return [collection] }
      return collections(in: child)
    }
  }

  func test_ZeroInitialCountIsNotCachedBeforeChildControllersAreAssigned() throws {
    let controller = TabViewController()
    controller.loadViewIfNeeded()
    let tabs = controller.tabView
    let views = collections(in: tabs)
    XCTAssertEqual(views.count, 2)
    // Force the initial count query before SearchTabViewController adds its children.
    for view in views { XCTAssertEqual(tabs.collectionView(view, numberOfItemsInSection: 0), 0) }
    controller.viewControllers = [UIViewController(), UIViewController()]
    for view in views {
      XCTAssertEqual(tabs.collectionView(view, numberOfItemsInSection: 0), 2)
      XCTAssertEqual(view.numberOfItems(inSection: 0), 2)
    }
  }

  func test_EmptyOrZeroSizedTabsDoNotScrollToAnInvalidItemOrConvertNaNToInt() throws {
    let controller = TabViewController()
    controller.loadViewIfNeeded()
    let tabs = controller.tabView
    tabs.frame = .zero
    tabs.selectedIndex = 0
    tabs.setNeedsLayout()
    tabs.layoutIfNeeded()
    for collection in collections(in: tabs) {
      collection.frame = .zero
      let size = tabs.collectionView(collection, layout: UICollectionViewFlowLayout(), sizeForItemAt: IndexPath(item: 0, section: 0))
      XCTAssertTrue(size.width.isFinite && size.height.isFinite)
      XCTAssertGreaterThanOrEqual(size.width, 0)
      XCTAssertGreaterThanOrEqual(size.height, 0)
      tabs.scrollViewDidEndDecelerating(collection)
    }
  }

  func test_SelectedPageSurvivesResizingWithoutRepeatedLayoutScrolling() throws {
    let controller = TabViewController()
    controller.loadViewIfNeeded()
    controller.viewControllers = [UIViewController(), UIViewController()]
    let tabs = controller.tabView
    tabs.selectedIndex = 1
    let content = try XCTUnwrap(tabs.subviews.compactMap { $0 as? UICollectionView }.first)
    for size in [CGSize(width: 320, height: 480), CGSize(width: 480, height: 320)] {
      tabs.frame = CGRect(origin: .zero, size: size)
      tabs.setNeedsLayout()
      tabs.layoutIfNeeded()
      tabs.layoutIfNeeded()
      XCTAssertEqual(tabs.selectedIndex, 1)
      XCTAssertEqual(content.contentOffset.x / content.bounds.width, 1, accuracy: 0.01)
    }
  }
}

final class MikshatCompassLocationIndependenceTests: XCTestCase {
  func test_LocationFreshnessDoesNotRequireSpeedOrCourse() {
    let stopped = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 24.7, longitude: 46.7),
                             altitude: 0, horizontalAccuracy: 5000, verticalAccuracy: -1,
                             course: -1, speed: -1, timestamp: Date())
    XCTAssertTrue(MikshatHeading.isFresh(stopped), "Approximate position remains a position even without speed/course")
    let old = CLLocation(coordinate: stopped.coordinate, altitude: 0, horizontalAccuracy: 20, verticalAccuracy: -1,
                         timestamp: Date(timeIntervalSinceNow: -600))
    XCTAssertFalse(MikshatHeading.isFresh(old), "Known coordinates must be labelled stale rather than live")
  }

  func test_HeadingOnlyServiceDoesNotStartGPS() {
    let wasStarted = LocationManager.isStarted()
    LocationManager.stop()
    MikshatHeadingSensor.shared.begin()
    defer {
      MikshatHeadingSensor.shared.end()
      if wasStarted { LocationManager.start() } else { LocationManager.stop() }
    }
    XCTAssertFalse(LocationManager.isStarted())
  }

  private func descendants<T: UIView>(of type: T.Type, in view: UIView) -> [T] {
    view.subviews.flatMap { child in
      (child as? T).map { [$0] } ?? []
    } + view.subviews.flatMap { descendants(of: type, in: $0) }
  }

  func test_GeneralSensorCompassWorksWithoutAnyLocation() throws {
    let controller = MikshatCompassViewController(target: nil, name: "Compass", general: true)
    controller.loadViewIfNeeded()
    controller.updateReadings(position: nil, reading: (degrees: 123, gps: false))
    let dial = try XCTUnwrap(descendants(of: MikshatCompassDial.self, in: controller.view).first)
    XCTAssertEqual(dial.heading, 123)
    XCTAssertEqual(dial.bearing, 123)
    XCTAssertEqual(dial.alpha, 1)
    XCTAssertEqual(dial.accessibilityValue, "123°")
    let labels = descendants(of: UILabel.self, in: controller.view)
    XCTAssertFalse(labels.contains { $0.text?.contains(L("mikshat_location_unavailable")) == true })
    XCTAssertTrue(labels.contains { $0.text == "—" })
  }

  func test_DestinationCompassUsesStalePositionButDoesNotPresentLiveSpeedOrArrival() throws {
    let destination = CLLocationCoordinate2D(latitude: 24.8, longitude: 46.8)
    let controller = MikshatCompassViewController(target: destination, name: "Destination")
    controller.loadViewIfNeeded()
    let cached = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 24.7, longitude: 46.7),
                           altitude: 0, horizontalAccuracy: 20, verticalAccuracy: -1,
                           course: 90, speed: 10, timestamp: Date(timeIntervalSinceNow: -600))
    controller.updateReadings(position: cached, reading: (degrees: 120, gps: false))
    let dial = try XCTUnwrap(descendants(of: MikshatCompassDial.self, in: controller.view).first)
    XCTAssertNotNil(dial.bearing)
    XCTAssertEqual(dial.alpha, 1)
    let labels = descendants(of: UILabel.self, in: controller.view)
    XCTAssertTrue(labels.contains { $0.text?.contains(L("mikshat_cached_location")) == true })
    XCTAssertFalse(labels.contains { $0.text == "36\n" + L("mikshat_kmh") })
    let distance = DistanceFormatter.distanceString(fromMeters: cached.distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)))
    XCTAssertTrue(labels.contains { $0.text == distance })
  }

  func test_DestinationCompassDoesNotInventBearingWhenPositionIsMissing() throws {
    let controller = MikshatCompassViewController(target: CLLocationCoordinate2D(latitude: 24.8, longitude: 46.8), name: "Destination")
    controller.loadViewIfNeeded()
    controller.updateReadings(position: nil, reading: (degrees: 120, gps: false))
    let dial = try XCTUnwrap(descendants(of: MikshatCompassDial.self, in: controller.view).first)
    XCTAssertNil(dial.bearing)
    XCTAssertEqual(dial.heading, 120)
  }

  func test_StationaryGPSWithFreshPositionWaitsForMovementInsteadOfMissingLocation() {
    let controller = MikshatCompassViewController(target: nil, name: "Compass", general: true)
    controller.loadViewIfNeeded()
    let position = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 24.7, longitude: 46.7),
                             altitude: 0, horizontalAccuracy: 20, verticalAccuracy: -1,
                             course: -1, speed: 0, timestamp: Date())
    controller.updateReadings(position: position, reading: (degrees: nil, gps: true))
    let labels = descendants(of: UILabel.self, in: controller.view)
    XCTAssertTrue(labels.contains { $0.text == L("mikshat_waiting") })
    XCTAssertFalse(labels.contains { $0.text?.contains(L("mikshat_location_unavailable")) == true })
  }
}

private final class SearchThemeFieldProbe: UITextField {
  var themeApplications = 0
  override func applyTheme() {
    themeApplications += 1
    super.applyTheme()
  }
}

private final class SearchThemeBarProbe: UISearchBar {
  var themeApplications = 0
  override func applyTheme() {
    themeApplications += 1
    super.applyTheme()
  }
}

final class SearchThemeWindowLifecycleTests: XCTestCase {
  func test_UIKitSearchControlsAttachAndDetachWithTheirThemeHooksActive() throws {
    _ = StyleManager.shared
    let window = try XCTUnwrap(MapsAppDelegate.theApp().window)
    let host = UIView(frame: window.bounds)
    host.isUserInteractionEnabled = false
    window.addSubview(host)
    defer { host.removeFromSuperview() }
    let field = SearchThemeFieldProbe(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
    field.setStyle(.background)
    let search = SearchThemeBarProbe(frame: CGRect(x: 0, y: 50, width: 300, height: 44))
    search.setStyle(.searchOnMapSearchBar)
    for _ in 0..<20 {
      host.addSubview(field)
      host.addSubview(search)
      XCTAssertTrue(field.window === window)
      XCTAssertTrue(search.window === window)
      XCTAssertTrue(field.isStyleApplied)
      XCTAssertTrue(search.isStyleApplied)
      field.removeFromSuperview()
      search.removeFromSuperview()
      XCTAssertNil(field.window)
      XCTAssertNil(search.window)
    }
    XCTAssertGreaterThanOrEqual(field.themeApplications, 20)
    XCTAssertGreaterThanOrEqual(search.themeApplications, 20)
    XCTAssertLessThan(field.themeApplications, 200, "A window notification must finish without recursively re-entering theming")
    XCTAssertLessThan(search.themeApplications, 200)
  }

  func test_ReinstallingThemeHooksDoesNotExchangeThemBackToTheOriginalMethods() throws {
    _ = StyleManager.shared
    // A second installation must be harmless. Calling twice here would hide an
    // exchange-based bug by undoing and then reinstalling the hooks.
    SwizzleStyle.swizzle()
    defer { SwizzleStyle.swizzle() }
    let window = try XCTUnwrap(MapsAppDelegate.theApp().window)
    let field = SearchThemeFieldProbe(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
    field.setStyle(.background)
    window.addSubview(field)
    defer { field.removeFromSuperview() }
    XCTAssertGreaterThan(field.themeApplications, 0)
    XCTAssertTrue(field.isStyleApplied)
  }

  func test_SearchOpensFocusesAndClosesRepeatedlyInNormalAndRoutingModes() throws {
    let map = try XCTUnwrap(MapViewController.shared())
    map.loadViewIfNeeded()
    let manager = SearchOnMapManager()
    defer { manager.close() }
    for routing in [false, true] {
      for _ in 0..<20 {
        manager.startSearching(isRouting: routing)
        let controller = try XCTUnwrap(manager.viewController)
        let attached = expectation(description: "Search attachment and deferred keyboard focus completed")
        DispatchQueue.main.async { attached.fulfill() }
        wait(for: [attached], timeout: 2)
        XCTAssertTrue(controller.parent === map)
        let bar = try XCTUnwrap(findSearchBar(in: controller.view))
        XCTAssertTrue(bar.searchTextField.isFirstResponder)
        manager.close()
        let detached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in controller.parent == nil }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [detached], timeout: 3), .completed)
      }
    }
  }

  private func findSearchBar(in view: UIView) -> UISearchBar? {
    if let bar = view as? UISearchBar { return bar }
    return view.subviews.lazy.compactMap { findSearchBar(in: $0) }.first
  }
}
