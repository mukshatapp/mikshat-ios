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

  private func assertActionsHidden(_ hidden: Bool, file: StaticString = #filePath, line: UInt = #line) {
    let settled = XCTNSPredicateExpectation(predicate: NSPredicate { [actions] _, _ in
      actions?.isHidden == hidden && actions?.alpha == (hidden ? 0 : 1)
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 2), .completed, file: file, line: line)
  }
}

final class MikshatHeadingSettingsTests: XCTestCase {
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
