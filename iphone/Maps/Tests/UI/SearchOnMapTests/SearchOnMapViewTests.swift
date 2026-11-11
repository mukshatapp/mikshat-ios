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

  func test_CoordinateInputLaysOutBothRowsWithPositiveNonoverlappingFieldWidths() throws {
    let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let input = MikshatCoordinateInputView()
    input.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(input)
    NSLayoutConstraint.activate([
      input.topAnchor.constraint(equalTo: host.topAnchor, constant: 16),
      input.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
      input.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16),
    ])
    let rows = input.arrangedSubviews.compactMap { $0 as? UIStackView }
    XCTAssertEqual(rows.count, 2)
    let widths: [CGFloat] = [320, 390, 844]
    for width in widths {
      host.frame.size.width = width
      host.setNeedsLayout()
      host.layoutIfNeeded()
      for row in rows {
        let fields = row.arrangedSubviews.compactMap { $0 as? UITextField }
        XCTAssertEqual(fields.count, 2)
        let degrees = try XCTUnwrap(fields.first)
        let minutes = try XCTUnwrap(fields.last)
        let degreeFrame = degrees.convert(degrees.bounds, to: row)
        let minuteFrame = minutes.convert(minutes.bounds, to: row)
        let details = coordinateConstraintDiagnostics(degrees: degrees, minutes: minutes)
        XCTAssertGreaterThan(degreeFrame.width, 0, details)
        XCTAssertGreaterThan(minuteFrame.width, degreeFrame.width, details)
        XCTAssertGreaterThan(degreeFrame.height, 0, details)
        XCTAssertGreaterThan(minuteFrame.height, 0, details)
        XCTAssertGreaterThanOrEqual(degreeFrame.minX, -1, details)
        XCTAssertLessThanOrEqual(minuteFrame.maxX, row.bounds.width + 1, details)
        XCTAssertLessThanOrEqual(degreeFrame.maxX, minuteFrame.minX, details)
        // The degree field is intentionally narrower than minutes. Use pixel
        // tolerance for the desired proportion, not exact multiplier equality.
        XCTAssertEqual(degreeFrame.width, minuteFrame.width * 0.65, accuracy: 1, details)
      }
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
    let history = try XCTUnwrap(tabs.children.compactMap { $0 as? SearchHistoryViewController }.first)
    let historyTable = try XCTUnwrap(history.view.subviews.compactMap { $0 as? UITableView }.first)
    XCTAssertEqual(searchController.view.safeAreaInsets.left, expectedLeadingInset, accuracy: 1)
    XCTAssertEqual(searchController.availableAreaView.frame.minX,
                   searchController.view.safeAreaInsets.left, accuracy: 1)
    XCTAssertEqual(tabs.view.safeAreaInsets.left, 0, accuracy: 1)
    XCTAssertEqual(historyTable.adjustedContentInset.left, 0, accuracy: 1)
    XCTAssertEqual(history.view.frame, tabs.view.bounds)
    XCTAssertEqual(historyTable.frame, history.view.bounds)
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
    let buttons = MWMSideButtons().view!
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
    let directions: [UISemanticContentAttribute] = [.forceLeftToRight, .forceRightToLeft]
    for direction in directions {
      let controller = TabViewController()
      controller.loadViewIfNeeded()
      controller.viewControllers = [UIViewController(), UIViewController()]
      let tabs = controller.tabView
      tabs.semanticContentAttribute = direction
      tabs.selectedIndex = 1
      let delegate = TabSelectionSpy()
      tabs.delegate = delegate
      let content = try XCTUnwrap(tabs.subviews.compactMap { $0 as? UICollectionView }.first)
      let header = try XCTUnwrap(collections(in: tabs).first { $0 !== content })
      let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first {
        $0.activationState == .foregroundActive
      }
      let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
      window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
      window.rootViewController = controller
      window.isHidden = false
      defer { window.isHidden = true }

      for size in [CGSize(width: 320, height: 480), CGSize(width: 480, height: 320)] {
        window.frame.size = size
        tabs.frame = CGRect(origin: .zero, size: size)
        tabs.setNeedsLayout()
        tabs.layoutIfNeeded()
        tabs.layoutIfNeeded()
        let expectedDirection: UIUserInterfaceLayoutDirection = direction == .forceRightToLeft ? .rightToLeft : .leftToRight
        XCTAssertEqual(content.effectiveUserInterfaceLayoutDirection, expectedDirection)
        XCTAssertEqual(tabs.selectedIndex, 1)
        try assertSelectedPage(1, in: controller, content: content, header: header)

        // Ending a drag on the same visible page must retain its logical identity,
        // even when that page is physically leftmost in RTL.
        tabs.scrollViewWillBeginDragging(content)
        tabs.scrollViewDidEndDecelerating(content)
        XCTAssertEqual(tabs.selectedIndex, 1)
        XCTAssertTrue(delegate.indices.isEmpty)
        try assertSelectedPage(1, in: controller, content: content, header: header)
      }

      let first = try XCTUnwrap(content.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
      let second = try XCTUnwrap(content.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
      let middle = CGPoint(x: (first.frame.midX + second.frame.midX) / 2 - content.bounds.width / 2,
                           y: content.contentOffset.y)
      content.setContentOffset(middle, animated: false)
      tabs.setNeedsLayout()
      tabs.layoutIfNeeded()
      tabs.layoutIfNeeded()
      XCTAssertEqual(content.contentOffset.x, middle.x, accuracy: 1, "Layout without a resize must not snap an in-progress swipe")

      tabs.collectionView(header, didSelectItemAt: IndexPath(item: 0, section: 0))
      let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        guard let attributes = content.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) else { return false }
        return abs(attributes.frame.minX - content.bounds.minX) < 1
      }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 2), .completed)
      tabs.layoutIfNeeded()
      XCTAssertEqual(tabs.selectedIndex, 0)
      XCTAssertEqual(delegate.indices, [0])
      try assertSelectedPage(0, in: controller, content: content, header: header)

      tabs.scrollViewWillBeginDragging(content)
      content.setContentOffset(CGPoint(x: second.frame.minX, y: content.contentOffset.y), animated: false)
      tabs.scrollViewDidEndDecelerating(content)
      tabs.layoutIfNeeded()
      XCTAssertEqual(tabs.selectedIndex, 1)
      XCTAssertEqual(delegate.indices, [0, 1])
      try assertSelectedPage(1, in: controller, content: content, header: header)
    }
  }

  private func assertSelectedPage(_ index: Int, in controller: TabViewController,
                                  content: UICollectionView, header: UICollectionView,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
    let path = IndexPath(item: index, section: 0)
    let attributes = try XCTUnwrap(content.layoutAttributesForItem(at: path), file: file, line: line)
    XCTAssertEqual(attributes.frame.minX, content.bounds.minX, accuracy: 1, file: file, line: line)
    XCTAssertEqual(attributes.frame.width, content.bounds.width, accuracy: 1, file: file, line: line)
    let center = CGPoint(x: content.bounds.midX, y: content.bounds.midY)
    XCTAssertEqual(content.indexPathForItem(at: center), path, file: file, line: line)
    let cell = try XCTUnwrap(content.cellForItem(at: path), file: file, line: line)
    XCTAssertTrue(controller.viewControllers[index].view.isDescendant(of: cell.contentView), file: file, line: line)
    XCTAssertEqual(header.indexPathsForSelectedItems, [path], file: file, line: line)

    let headerAttributes = try XCTUnwrap(header.layoutAttributesForItem(at: path), file: file, line: line)
    let expected = header.convert(headerAttributes.frame, to: controller.tabView)
    let indicator = try XCTUnwrap(header.superview?.subviews.first {
      $0.accessibilityIdentifier == "tab-selection-indicator"
    }, file: file, line: line)
    let actual = indicator.convert(indicator.bounds, to: controller.tabView)
    XCTAssertEqual(actual.minX, expected.minX, accuracy: 1, file: file, line: line)
    XCTAssertEqual(actual.width, expected.width, accuracy: 1, file: file, line: line)
  }

  private final class TabSelectionSpy: TabViewDelegate {
    var indices: [Int] = []
    func tabView(_: TabView, didSelectTabAt index: Int) { indices.append(index) }
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
    let restoreHistory = prepareCoordinateHistoryIfRendererRequested()
    defer { restoreHistory?() }
    try requireRenderedArabicMapIfRequested(map)
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
        try requireAttachedCoordinateHistoryIndicatorIfRequested(in: controller.view)
        manager.close()
        let detached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in controller.parent == nil }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [detached], timeout: 3), .completed)
      }
    }
  }

  func test_GlobalSearchManagerOpensWithDashboardObserversInPrepareAndNavigation() throws {
    let map = try XCTUnwrap(MapViewController.shared())
    map.loadViewIfNeeded()
    let restoreHistory = prepareCoordinateHistoryIfRendererRequested()
    defer { restoreHistory?() }
    try requireRenderedArabicMapIfRequested(map)
    let manager = map.searchManager
    let dashboard = MWMNavigationDashboardManager.shared()
    if let existing = manager.viewController {
      manager.close()
      let detached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in existing.parent == nil }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [detached], timeout: 3), .completed)
    }
    defer {
      manager.close()
      dashboard.onRouteStop()
    }
    // This is dashboard/observer integration, not a simulated GPS trip. A local
    // SearchOnMapManager would skip these real dashboard notifications entirely.
    for navigation in [false, true] {
      dashboard.onRoutePrepare()
      if navigation { dashboard.onRouteStart() }
      for routing in [false, true] {
        for _ in 0..<3 {
          manager.startSearching(isRouting: routing)
          let controller = try XCTUnwrap(manager.viewController)
          let focused = expectation(description: "Global search notification and keyboard focus complete")
          DispatchQueue.main.async { focused.fulfill() }
          wait(for: [focused], timeout: 2)
          XCTAssertTrue(controller.parent === map)
          let bar = try XCTUnwrap(findSearchBar(in: controller.view))
          XCTAssertTrue(bar.searchTextField.isFirstResponder)
          try requireAttachedCoordinateHistoryIndicatorIfRequested(in: controller.view)
          XCTAssertEqual(dashboard.state, navigation ? .navigation : .prepare)
          manager.close()
          let detached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in controller.parent == nil }, object: nil)
          XCTAssertEqual(XCTWaiter.wait(for: [detached], timeout: 3), .completed)
        }
      }
    }
  }

  private func findSearchBar(in view: UIView) -> UISearchBar? {
    if let bar = view as? UISearchBar { return bar }
    return view.subviews.lazy.compactMap { self.findSearchBar(in: $0) }.first
  }
}

// Test-only helpers for SearchThemeWindowLifecycleTests. After loading the map:
//   let restoreHistory = prepareCoordinateHistoryIfRendererRequested()
//   defer { restoreHistory?() }
//   try requireRenderedArabicMapIfRequested(map)
// After each open has focused its search field:
//   try requireAttachedCoordinateHistoryIndicatorIfRequested(in: controller.view)
// Ordinary -IsTests runs are unchanged. Use a fresh simulator: the public native
// history API restores query text/order, but does not expose each saved locale.
// The workflow must pregrant location and run:
//   xcrun simctl location <UDID> set 24.7136,46.6753
// Only this simulator profile starts the existing native LocationManager and
// waits for its fresh synthetic position. No hardware heading is required.

private let rendererHistoryQuery = "24.71360000,46.67530000"
private let rendererHistoryCoordinate = CLLocationCoordinate2D(latitude: 24.7136, longitude: 46.6753)

private func prepareCoordinateHistoryIfRendererRequested() -> (() -> Void)? {
  guard ProcessInfo.processInfo.arguments.contains("-MikshatRequireRenderer") else { return nil }
  XCTAssertTrue(Thread.isMainThread)
  let defaults = UserDefaults.standard
  let selectedIndexKey = "SearchTabViewController_selectedIndexKey"
  let locationsKey = "mikshat_search_locations"
  let previousQueries = MWMSearchFrameworkHelper.lastSearchQueries()
  let previousEnabled = Settings.searchHistoryEnabled()
  let previousIndex = defaults.object(forKey: selectedIndexKey)
  let previousLocations = defaults.object(forKey: locationsKey)
  Settings.setSearchHistoryEnabled(true)
  Search.save(SearchQuery(rendererHistoryQuery, source: .typedText))
  MikshatSearchLocations.remember(rendererHistoryCoordinate, query: rendererHistoryQuery)
  defaults.set(0, forKey: selectedIndexKey)
  XCTAssertEqual(MWMSearchFrameworkHelper.lastSearchQueries().first, rendererHistoryQuery)
  return {
    Settings.setSearchHistoryEnabled(true)
    MWMSearchFrameworkHelper.clearSearchHistory()
    for query in previousQueries.reversed() {
      Search.save(SearchQuery(query, source: .history))
    }
    Settings.setSearchHistoryEnabled(previousEnabled)
    if let previousIndex { defaults.set(previousIndex, forKey: selectedIndexKey) }
    else { defaults.removeObject(forKey: selectedIndexKey) }
    if let previousLocations { defaults.set(previousLocations, forKey: locationsKey) }
    else { defaults.removeObject(forKey: locationsKey) }
    XCTAssertEqual(MWMSearchFrameworkHelper.lastSearchQueries(), previousQueries)
  }
}

private func requireRenderedArabicMapIfRequested(_ map: MapViewController) throws {
  guard ProcessInfo.processInfo.arguments.contains("-MikshatRequireRenderer") else { return }
  guard !MapsAppDelegate.isTestsEnvironment() else {
    throw NSError(domain: "MikshatSearchRendererSetup", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Remove -IsTests: it disables normal Drape creation."])
  }
  XCTAssertTrue(Thread.isMainThread)
  let language = Locale.preferredLanguages.first ?? ""
  guard language.hasPrefix("ar") else {
    throw NSError(domain: "MikshatSearchRendererSetup", code: 2,
                  userInfo: [NSLocalizedDescriptionKey: "Arabic launch arguments were not applied: \(language)"])
  }
  XCTAssertEqual(UIView.userInterfaceLayoutDirection(for: .unspecified), .rightToLeft)
  // Hosted tests can start while UIKit is still activating the application.
  // Wait for its real foreground window before requesting normal map layout.
  let foregroundReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
    guard UIApplication.shared.applicationState == .active,
          let window = map.viewIfLoaded?.window else { return false }
    return window.isKeyWindow && !window.isHidden && window.alpha > 0 && !window.bounds.isEmpty
  }, object: nil)
  let foregroundOutcome = XCTWaiter.wait(for: [foregroundReady], timeout: 20)
  guard foregroundOutcome == .completed else {
    let window = map.viewIfLoaded?.window
    try? appendRendererCoverage(event: "setup-failed", map: map,
                                extra: ["stage": "application-activation",
                                        "applicationState": UIApplication.shared.applicationState.rawValue,
                                        "windowAttached": window != nil,
                                        "windowKey": window?.isKeyWindow ?? false,
                                        "windowHidden": window?.isHidden ?? true,
                                        "waitOutcome": String(describing: foregroundOutcome)])
    throw NSError(domain: "MikshatSearchRendererSetup", code: 7,
                  userInfo: [NSLocalizedDescriptionKey: "Application did not become active with a visible key window within 20 seconds; search-rendering coverage was not executed."])
  }
  XCTAssertEqual(map.view.effectiveUserInterfaceLayoutDirection, .rightToLeft)
  let window = try XCTUnwrap(map.view.window)
  XCTAssertFalse(window.isHidden)
  XCTAssertTrue(window.isKeyWindow)
  XCTAssertEqual(UIApplication.shared.applicationState, .active)
  // Exercise the normal MapViewController layout path; do not explicitly create
  // a renderer here, as that would conceal an incorrect launch configuration.
  map.view.setNeedsLayout()
  map.view.layoutIfNeeded()
  let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
    map.mapView.drapeEngineCreated && map.mapView.graphicContextInitialized
  }, object: nil)
  let outcome = XCTWaiter.wait(for: [ready], timeout: 30)
  XCTAssertEqual(outcome, .completed, "Normal Drape creation and both graphics contexts must complete before opening search")
  guard outcome == .completed else {
    throw NSError(domain: "MikshatSearchRendererSetup", code: 3,
                  userInfo: [NSLocalizedDescriptionKey: "Renderer did not become ready; this is not an executed search-rendering regression test."])
  }
  let layerClass = String(describing: type(of: map.mapView.layer))
  XCTAssertEqual(layerClass, "CAMetalLayer", "Do not describe an OpenGL fallback as Metal coverage")
  print("MikshatSearch renderer-ready=true layer=\(layerClass) language=\(language) direction=RTL")
  try appendRendererCoverage(event: "renderer-ready", map: map, extra: [:])
  try requireSyntheticSimulatorLocationIfRequested(map)
}

private func requireSyntheticSimulatorLocationIfRequested(_ map: MapViewController) throws {
  guard ProcessInfo.processInfo.arguments.contains("-MikshatRequireRenderer") else { return }
#if targetEnvironment(simulator)
  XCTAssertTrue(Thread.isMainThread)
  // Starting the production owner is idempotent; do not inject CLLocation into
  // Framework or call the heading sensor directly from this diagnostic test.
  LocationManager.start()
  let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
    guard let fix = MikshatHeading.currentLocation else { return false }
    let expected = CLLocation(latitude: rendererHistoryCoordinate.latitude,
                              longitude: rendererHistoryCoordinate.longitude)
    return fix.distance(from: expected) <= 100
  }, object: nil)
  let outcome = XCTWaiter.wait(for: [ready], timeout: 20)
  guard outcome == .completed else {
    try? appendRendererCoverage(event: "gps-setup-failed", map: map,
                                extra: ["syntheticPosition": true,
                                        "freshLocationAvailable": MikshatHeading.currentLocation != nil,
                                        "locationProhibited": LocationManager.isLocationProhibited(),
                                        "nativeLocationStarted": LocationManager.isStarted()])
    throw NSError(domain: "MikshatSearchRendererSetup", code: 4,
                  userInfo: [NSLocalizedDescriptionKey: "Synthetic simulator GPS setup failed before search: verify simctl location and pregranted permission; search history/heading coverage was not executed."])
  }
  try appendRendererCoverage(event: "gps-ready", map: map,
                             extra: ["syntheticPosition": true,
                                     "freshLocationAvailable": true,
                                     "sensorHeadingRequired": false])
#else
  try? appendRendererCoverage(event: "gps-setup-failed", map: map,
                              extra: ["syntheticPosition": false,
                                      "reason": "This diagnostic profile requires an iOS simulator."])
  throw NSError(domain: "MikshatSearchRendererSetup", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Use an iOS simulator for the controlled synthetic GPS profile."])
#endif
}

private func requireAttachedCoordinateHistoryIndicatorIfRequested(in view: UIView) throws {
  guard ProcessInfo.processInfo.arguments.contains("-MikshatRequireRenderer") else { return }
  let map = try XCTUnwrap(MapViewController.shared())
  guard MikshatHeading.currentLocation != nil else {
    try? appendRendererCoverage(event: "gps-setup-failed", map: map,
                                extra: ["syntheticPosition": true,
                                        "freshLocationAvailable": false,
                                        "reason": "The synthetic fix became stale before a history attachment assertion."])
    throw NSError(domain: "MikshatSearchRendererSetup", code: 6,
                  userInfo: [NSLocalizedDescriptionKey: "Synthetic GPS became stale; this iteration cannot establish history reading() coverage."])
  }
  view.setNeedsLayout()
  view.layoutIfNeeded()
  let attached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
    attachedCoordinateHistoryIndicator(in: view) != nil
  }, object: nil)
  let outcome = XCTWaiter.wait(for: [attached], timeout: 5)
  XCTAssertEqual(outcome, .completed, "Seeded coordinate history must attach its direction indicator in an on-screen history cell")
  let indicator = try XCTUnwrap(attachedCoordinateHistoryIndicator(in: view))
  // Without a hardware heading the indicator correctly has alpha == 0. Its
  // on-screen cell/window attachment proves the history lifecycle was exercised.
  try appendRendererCoverage(event: "history-indicator-attached", map: map,
                             extra: ["indicatorAlpha": indicator.alpha,
                                     "freshLocationAvailable": MikshatHeading.currentLocation != nil])
}

private func attachedCoordinateHistoryIndicator(in view: UIView) -> MikshatDirectionIndicator? {
  if let indicator = view as? MikshatDirectionIndicator,
     let target = indicator.target,
     abs(target.latitude - rendererHistoryCoordinate.latitude) < 0.00000001,
     abs(target.longitude - rendererHistoryCoordinate.longitude) < 0.00000001,
     let window = indicator.window,
     !indicator.isHidden,
     !indicator.bounds.isEmpty,
     indicator.convert(indicator.bounds, to: window).intersects(window.bounds) {
    var ancestor = indicator.superview
    var hasVisibleHistoryCell = false
    while let parent = ancestor {
      if parent.isHidden || parent.alpha <= 0 { return nil }
      if parent is SearchHistoryCell { hasVisibleHistoryCell = true }
      ancestor = parent.superview
    }
    if hasVisibleHistoryCell { return indicator }
  }
  for subview in view.subviews {
    if let indicator = attachedCoordinateHistoryIndicator(in: subview) { return indicator }
  }
  return nil
}

private func appendRendererCoverage(event: String, map: MapViewController, extra: [String: Any]) throws {
  var entry: [String: Any] = [
    "event": event,
    "timestamp": ISO8601DateFormatter().string(from: Date()),
    "layer": String(describing: type(of: map.mapView.layer)),
    "language": Locale.preferredLanguages.first ?? "",
    "direction": map.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? "RTL" : "LTR",
    "device": UIDevice.current.model,
    "systemVersion": UIDevice.current.systemVersion,
    "active": UIApplication.shared.applicationState == .active,
    "rendererReady": map.mapView.drapeEngineCreated,
    "graphicsReady": map.mapView.graphicContextInitialized,
  ]
  entry.merge(extra) { _, new in new }
  var data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
  data.append(0x0a)
  let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
  let url = directory.appendingPathComponent("mikshat-renderer-coverage.jsonl")
  if !FileManager.default.fileExists(atPath: url.path) {
    XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
  }
  let file = try FileHandle(forWritingTo: url)
  defer { try? file.close() }
  try file.seekToEnd()
  try file.write(contentsOf: data)
}


private func coordinateConstraintDiagnostics(degrees: UITextField, minutes: UITextField) -> String {
  var descriptions: [String] = []
  var ancestor: UIView? = degrees
  while let owner = ancestor {
    for constraint in owner.constraints where constraint.firstItem === degrees || constraint.firstItem === minutes
      || constraint.secondItem === degrees || constraint.secondItem === minutes {
      let multiplier = String(format: "%.17g", Double(constraint.multiplier))
      descriptions.append("owner=\(type(of: owner)) active=\(constraint.isActive) multiplier=\(multiplier) \(constraint)")
    }
    ancestor = owner.superview
  }
  return "degrees=\(degrees.frame) minutes=\(minutes.frame)\n" + descriptions.joined(separator: "\n")
}
