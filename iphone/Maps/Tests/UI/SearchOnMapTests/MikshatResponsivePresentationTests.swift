@testable import Organic_Maps__Debug_
import XCTest
import UIKit
import CoreLocation

final class MikshatResponsivePresentationTests: XCTestCase {
  @MainActor
  func testSearchSheetAndNativeHeaderStayCenteredWhenTheContainerRotates() throws {
    let map = try XCTUnwrap(MapViewController.shared())
    map.loadViewIfNeeded()
    for (name, portrait) in presentationViewports {
      let search = SearchOnMapViewController()
      let host = PresentationUIKitHost(search, size: portrait)
      defer { host.close() }
      var model = SearchOnMap.ViewModel.initial
      model.isTyping = false
      model.contentState = .results(.empty)
      UIView.performWithoutAnimation { search.render(model) }
      for (orientation, size) in [("portrait", portrait), ("landscape", CGSize(width: portrait.height, height: portrait.width)),
                                   ("portrait-restored", portrait)] {
        host.resize(size)
        let sheet = search.availableAreaView
        XCTAssertEqual(sheet.accessibilityIdentifier, "search.sheet")
        XCTAssertTrue(sheet.window === host.window)
        XCTAssertGreaterThan(sheet.bounds.width, 0)
        let safe = search.view.safeAreaLayoutGuide.layoutFrame
        // A wide phone window can retain a regular vertical size class (for
        // example the large resizable viewport below). The production sheet
        // follows its actual aspect ratio, not just that trait shortcut.
        let bounded = search.traitCollection.userInterfaceIdiom == .pad || size.width > size.height
        if bounded {
          assertHorizontallyContained(sheet.frame, in: safe)
          XCTAssertEqual(sheet.frame.midX, safe.midX, accuracy: 1,
                         "Search must center in its container's safe area after \(name)-\(orientation)")
          XCTAssertEqual(sheet.frame.midY, safe.midY, accuracy: 1)
          XCTAssertTrue(safe.insetBy(dx: -1, dy: -1).contains(sheet.frame))
        } else {
          XCTAssertEqual(sheet.frame.width, search.view.bounds.width, accuracy: 1)
          XCTAssertEqual(sheet.frame.midX, search.view.bounds.midX, accuracy: 1)
        }
        let header = try XCTUnwrap(presentationDescendants(sheet).compactMap { $0 as? SearchOnMapHeaderView }.first)
        let bar = try XCTUnwrap(presentationDescendants(header).compactMap { $0 as? UISearchBar }.first)
        let results = try XCTUnwrap(presentationDescendants(sheet).compactMap { $0 as? UITableView }
          .first { $0.dataSource === search })
        XCTAssertEqual(results.contentInset.left, 0, accuracy: 1)
        XCTAssertEqual(results.contentInset.right, 0, accuracy: 1)
        if bounded {
          XCTAssertEqual(results.contentInset.bottom, 0, accuracy: 1,
                         "An expanded sheet contained by its viewport must not add off-screen translation padding")
        }
        XCTAssertEqual(header.bounds.width, sheet.bounds.width, accuracy: 1)
        XCTAssertFalse(header.hasAmbiguousLayout)
        XCTAssertFalse(bar.isFirstResponder)
        XCTAssertFalse(bar.searchTextField.isFirstResponder)
        assertHorizontallyContained(header.convert(header.bounds, to: sheet), in: sheet.bounds)
        if bounded {
          XCTAssertTrue(sheet.bounds.insetBy(dx: -1, dy: -1).contains(header.convert(header.bounds, to: sheet)),
                        "The native search header must fit inside its expanded sheet")
        }
        assertHorizontallyContained(bar.searchTextField.convert(bar.searchTextField.bounds, to: header), in: header.bounds)
        XCTAssertGreaterThan(bar.searchTextField.bounds.width, 0)
        let fields = presentationDescendants(header).compactMap { $0 as? UITextField }
          .filter { $0 !== bar.searchTextField }
        XCTAssertEqual(fields.count, 4, "The real coordinate entry must remain part of the search header")
        for field in fields {
          XCTAssertGreaterThan(field.bounds.width, 0)
          assertHorizontallyContained(field.convert(field.bounds, to: header), in: header.bounds)
        }
        try attachPresentationScreenshot(host.container.view, name: "search-\(name)-\(orientation)")
      }
    }
  }

  @MainActor
  func testNativeMenuAndMapPointPickerRespectTheSameSafeHorizontalCenter() throws {
    for (name, portrait) in presentationViewports {
      // Freeze the rows while exercising the production controller, XIB and native cells.
      // The production presenter needs a rendered map viewport to resolve the current country.
      let menu = BottomMenuViewController(nibName: nil, bundle: nil)
      menu.presenter = PresentationMenuRows()
      let menuHost = PresentationUIKitHost(menu, size: portrait)
      defer { menuHost.close() }
      let picker = MapPointPickerViewController(title: "اختر نقطة", hint: "حرك الخريطة لتحديد النقطة المختارة",
                                                enableBounds: false, initialMercatorPosition: nil,
                                                shouldChangeViewport: false)
      // Load the production header as an ordinary child. Choosing a point is a separate
      // framework operation and is already covered by MapPointPickerViewControllerTests.
      let pickerHost = PresentationUIKitHost(picker, size: portrait)
      defer { pickerHost.close() }
      for (orientation, size) in [("portrait", portrait), ("landscape", CGSize(width: portrait.height, height: portrait.width)),
                                   ("portrait-restored", portrait)] {
        menuHost.resize(size)
        pickerHost.resize(size)
        let panel = try presentationElement("menu.panel", in: menu.view)
        let menuSafe = menu.view.safeAreaLayoutGuide.layoutFrame
        let panelRect = panel.convert(panel.bounds, to: menu.view)
        XCTAssertGreaterThan(panelRect.height, 0)
        assertHorizontallyContained(panelRect, in: menuSafe)
        XCTAssertTrue(menuSafe.insetBy(dx: -1, dy: -1).contains(panelRect),
                      "The complete native menu must fit inside its safe area after \(name)-\(orientation)")
        XCTAssertEqual(panelRect.midX, menuSafe.midX, accuracy: 1,
                       "The native menu must center after \(name)-\(orientation)")
        XCTAssertFalse(panel.hasAmbiguousLayout)
        XCTAssertEqual(menu.tableView.numberOfSections, 2)
        XCTAssertEqual(menu.tableView.numberOfRows(inSection: 0), 1)
        XCTAssertEqual(menu.tableView.numberOfRows(inSection: 1), 6)
        XCTAssertFalse(menu.tableView.visibleCells.isEmpty)
        try attachPresentationScreenshot(menuHost.container.view, name: "menu-\(name)-\(orientation)")

        let safe = picker.view.safeAreaLayoutGuide.layoutFrame
        let title = try presentationElement("mapPointPicker.title", in: picker.view)
        let hint = try presentationElement("mapPointPicker.hint", in: picker.view)
        let cancel = try presentationElement("mapPointPicker.cancel", in: picker.view)
        let done = try presentationElement("mapPointPicker.done", in: picker.view)
        for view in [title, hint, cancel, done] {
          XCTAssertFalse(view.isHidden)
          XCTAssertGreaterThan(view.bounds.width, 0)
          XCTAssertGreaterThan(view.bounds.height, 0)
          assertHorizontallyContained(view.convert(view.bounds, to: picker.view), in: safe)
        }
        let titleRect = title.convert(title.bounds, to: picker.view)
        XCTAssertEqual(titleRect.midX, safe.midX, accuracy: 1)
        XCTAssertEqual(hint.convert(hint.bounds, to: picker.view).midX, safe.midX, accuracy: 1)
        XCTAssertFalse(titleRect.intersects(cancel.convert(cancel.bounds, to: picker.view)))
        XCTAssertFalse(titleRect.intersects(done.convert(done.bounds, to: picker.view)))
        for button in [cancel, done] {
          XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
          XCTAssertFalse((button.accessibilityLabel ?? "").isEmpty)
        }
        XCTAssertFalse(picker.view.hasAmbiguousLayout)
        try attachPresentationScreenshot(pickerHost.container.view, name: "map-picker-\(name)-\(orientation)")
      }
    }
  }

  @MainActor
  private func attachPresentationScreenshot(_ view: UIView, name: String) throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { view.layer.render(in: $0.cgContext) }
    XCTAssertNotNil(image.pngData())
    let attachment = XCTAttachment(image: image)
    attachment.name = "responsive-presentation-\(name)-fixture"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

// Exercise the production MapViewController, its actual storyboard outlets and
// child/presentation containers in the real app window. These cases use public
// scene (phone) or physical-device (iPad CI) rotation and verify UIKit changed geometry;
// resizing an isolated preview would miss the broken full place-page hierarchy.
// The ordinary hosted suite still uses -IsTests (no Drape), so this is UIKit
// integration coverage, not a rendered-map/GPS-trip or memory-performance claim.
@available(iOS 16.0, *)
final class MikshatMapSceneLayoutTests: XCTestCase {
  @MainActor
  func testSelectedPointUsesTheRealBottomSheetAndKeepsAllContentReachableAfterSceneRotation() async throws {
    let (map, window, scene) = try await attachedMapScene()
    defer { map.dismissPlacePage() }
    let point = CLLocationCoordinate2D(latitude: 24.65001, longitude: 46.71002)
    for orientation in [UIInterfaceOrientation.portrait, .landscapeRight, .portrait] {
      try await rotateMapScene(scene, window: window, map: map, to: orientation)
      for title in ["شارع سكني", "نقطة مختارة على الخريطة باسم طويل"] {
        MikshatNavigationCoordinator.restoreDestinationSelection(coordinate: point, title: title)
        try await sceneWait("The actual selected place-page child must be attached") {
          guard PlacePageData.hasData,
                let page = map.children.compactMap({ $0 as? PlacePageViewController }).first,
                page.viewIfLoaded?.window === window else { return false }
          let data = PlacePageData(localizationProvider: OpeinigHoursLocalization())
          return data.previewData.title == title
        }
        let page = try XCTUnwrap(map.children.compactMap { $0 as? PlacePageViewController }.first)
        await settleMapScene(map)
        let host = try sceneElement("placePage.host", in: map.view)
        let background = try sceneElement("placePage.background", in: page.view)
        let header = try sceneElement("placePage.headerContent", in: page.view)
        let actions = try sceneElement("placePage.actions", in: page.view)
        let safe = map.view.safeAreaLayoutGuide.layoutFrame
        let hostRect = host.convert(host.bounds, to: map.view)
        XCTAssertEqual(hostRect.midX, safe.midX, accuracy: 1)
        XCTAssertEqual(hostRect.maxY, map.view.bounds.maxY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(host.bounds.width, min(600, safe.width - 32) - 1,
                                   "The real point card must not collapse into a narrow sidebar")
        XCTAssertEqual(page.view.bounds.width, host.bounds.width, accuracy: 1)
        XCTAssertEqual(header.bounds.width, host.bounds.width, accuracy: 1)
        let visibleCard = background.convert(background.bounds, to: map.view).intersection(map.view.bounds)
        XCTAssertEqual(visibleCard.maxY, map.view.bounds.maxY, accuracy: 1,
                       "The visible card, not just its transparent host, must reach the bottom")
        XCTAssertGreaterThan(visibleCard.height, 150)
        XCTAssertGreaterThanOrEqual(visibleCard.minY, safe.minY - 1)
        for identifier in ["placePage.title", "placePage.close", "placePage.share",
                           "placePage.coordinates.ddm.latitude", "placePage.coordinates.ddm.longitude",
                           "placePage.coordinates.ddm.copy", "placePage.coordinates.toggle"] {
          let element = try sceneElement(identifier, in: page.view)
          assertSceneVisible(element, in: map.view, context: identifier)
        }
        assertSceneVisible(actions, in: map.view, context: "fixed save/go actions")
        XCTAssertGreaterThanOrEqual(actions.bounds.height, 44)
        try sceneScreenshot(window, name: "selected-point-initial-\(orientation.rawValue)-\(title.count)")
        let weather = try sceneElement("placePage.weather", in: page.view)
        if UIDevice.current.userInterfaceIdiom == .pad || orientation.isLandscape {
          assertSceneVisible(weather, in: map.view, context: "weather in the widened initial point card")
        } else {
          // Phone portrait keeps its existing collapsed preview. Its weather
          // entry may require the ordinary sheet expansion/scroll interaction.
          page.scrollToReveal(weather)
          await settleMapScene(map)
          assertSceneVisible(weather, in: map.view, context: "reachable portrait weather")
        }
        let toggle = try XCTUnwrap(try sceneElement("placePage.coordinates.toggle", in: page.view) as? UIButton)
        page.scrollToReveal(toggle)
        await settleMapScene(map)
        toggle.sendActions(for: .touchUpInside)
        await settleMapScene(map)
        for format in ["dd", "dms"] {
          let row = try sceneElement("placePage.coordinates." + format, in: page.view)
          page.scrollToReveal(row)
          await settleMapScene(map)
          for suffix in ["latitude", "longitude", "copy"] {
            let element = try sceneElement("placePage.coordinates." + format + "." + suffix, in: page.view)
            assertSceneVisible(element, in: map.view, context: "expanded " + format)
          }
        }
        try sceneScreenshot(window, name: "selected-point-expanded-\(orientation.rawValue)-\(title.count)")
        map.dismissPlacePage()
        await settleMapScene(map)
      }
    }
    try await assertActualWeatherSheet(in: map, window: window, scene: scene)
  }

  @MainActor
  func testRealHomePreviewAndTripContainersStayPlacedAcrossPortraitLandscapePortrait() async throws {
    let (map, window, scene) = try await attachedMapScene()
    let manager = MWMNavigationDashboardManager.shared()
    let controls = map.controlsManager
    defer { manager.onRouteStop(); controls.menuState = .inactive }
    controls.hidden = false
    controls.menuState = .inactive
    try await rotateMapScene(scene, window: window, map: map, to: .landscapeRight)
    await settleMapScene(map)
    let home = controls.tabBarController!
    let homeContent = try sceneElement("home.bottomBar.content", in: home.view)
    assertSceneVisible(homeContent, in: map.view, context: "actual home bar")
    if UIDevice.current.userInterfaceIdiom == .phone {
      let safe = map.view.safeAreaLayoutGuide.layoutFrame
      let rect = homeContent.convert(homeContent.bounds, to: map.view)
      XCTAssertGreaterThanOrEqual(rect.width, safe.width - 26)
      XCTAssertLessThan(rect.height, 130)
      for identifier in ["home.settings", "home.saveShare", "home.record", "home.bookmarks"] {
        let button = try XCTUnwrap(try sceneElement(identifier, in: home.view) as? UIButton)
        assertSceneVisible(button, in: map.view, context: identifier)
        if let label = button.titleLabel, let text = label.text {
          for word in text.components(separatedBy: .whitespacesAndNewlines).filter({ !$0.isEmpty }) {
            XCTAssertLessThanOrEqual((word as NSString).size(withAttributes: [.font: label.font!]).width,
                                     label.bounds.width + 1, "Home captions must not split a word into letters")
          }
        }
      }
      let saveShare = try XCTUnwrap(try sceneElement("home.saveShare", in: home.view) as? UIButton)
      saveShare.sendActions(for: .touchUpInside)
      try await sceneWait("Save/share must use the actual presentation path") { map.presentedViewController != nil }
      let menu = try XCTUnwrap(map.presentedViewController)
      await settleMapScene(map)
      let card = try sceneElement("saveShare.card", in: menu.view)
      assertSceneVisible(card, in: window, context: "compact save/share")
      XCTAssertLessThanOrEqual(card.bounds.height, 300)
      for identifier in ["saveShare.save", "saveShare.share", "saveShare.cancel"] {
        let button = try sceneElement(identifier, in: menu.view)
        assertSceneVisible(button, in: window, context: identifier)
        XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
      }
      try sceneScreenshot(window, name: "save-share-landscape")
      map.dismiss(animated: false)
      await settleMapScene(map)
    }
    try sceneScreenshot(window, name: "home-landscape")
    manager.onRoutePrepare()
    await settleMapScene(map)
    let dashboard = try XCTUnwrap(map.children.compactMap { $0 as? NavigationDashboardViewController }.first)
    var model = NavigationDashboard.ViewModel.initial
    model.dashboardState = .ready
    model.presentationStep = .regular
    model.progress = 1
    model.routerType = .vehicle
    model.estimates = NSAttributedString(string: "المسافة: ٣٫٦ كم")
    model.navigationInfo.state = .hidden
    model.entity = sceneNavigationEntity()
    for orientation in [UIInterfaceOrientation.portrait, .landscapeRight, .portrait] {
      try await rotateMapScene(scene, window: window, map: map, to: orientation)
      dashboard.render(model)
      await settleMapScene(map)
      let preview = try sceneElement("navigation.preview", in: dashboard.view)
      let rect = preview.convert(preview.bounds, to: map.view)
      let safe = map.view.safeAreaLayoutGuide.layoutFrame
      if UIDevice.current.userInterfaceIdiom == .pad || orientation.isLandscape {
        XCTAssertEqual(rect.midX, safe.midX, accuracy: 1)
        XCTAssertEqual(rect.midY, safe.midY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(rect.width, min(600, safe.width - 24) - 1)
        XCTAssertLessThanOrEqual(rect.height, min(300, safe.height))
        XCTAssertTrue(safe.insetBy(dx: -1, dy: -1).contains(rect))
      }
      let start = try sceneElement("navigation.preview.start", in: dashboard.view)
      assertSceneVisible(start, in: map.view, context: "prestart route action")
      XCTAssertGreaterThanOrEqual(start.bounds.height, 44)
      try sceneScreenshot(window, name: "prestart-\(orientation.rawValue)")
    }
    manager.onRouteStart()
    model.dashboardState = .navigation
    model.presentationStep = .hidden
    model.navigationInfo.state = .navigation
    for orientation in [UIInterfaceOrientation.portrait, .landscapeRight, .portrait, .landscapeLeft, .portrait] {
      try await rotateMapScene(scene, window: window, map: map, to: orientation)
      model.navigationInfo.availableArea = map.view.bounds
      dashboard.render(model)
      await settleMapScene(map)
      let card = try sceneElement("navigation.infoCard", in: dashboard.view)
      try assertSceneTripLayout(card, in: map.view, orientation: orientation)
      let expand = NSSelectorFromString("extendAction")
      XCTAssertTrue(card.responds(to: expand))
      UIView.performWithoutAnimation { _ = card.perform(expand) }
      await settleMapScene(map)
      for identifier in ["navigation.stop", "navigation.sound", "navigation.settings"] {
        let action = try sceneElement(identifier, in: card)
        assertSceneVisible(action, in: map.view, context: identifier)
        XCTAssertGreaterThanOrEqual(action.bounds.width, 44)
        XCTAssertGreaterThanOrEqual(action.bounds.height, 44)
      }
      try sceneScreenshot(window, name: "native-trip-\(orientation.rawValue)")
      UIView.performWithoutAnimation { _ = card.perform(expand) }
    }
    manager.onRouteStop()
    await settleMapScene(map)
    controls.menuState = .hidden
    let destination = CLLocationCoordinate2D(latitude: 24.66, longitude: 46.72)
    let origin = CLLocation(latitude: 24.65, longitude: 46.71)
    let direct = MikshatDirectGuidanceView(target: destination, origin: origin)
    direct.translatesAutoresizingMaskIntoConstraints = false
    map.view.insertSubview(direct, belowSubview: map.placePageContainer)
    direct.installPlacement(in: map.view)
    let actions = MikshatNavigationActionsView()
    actions.install(in: map.view, above: direct)
    defer { direct.stop(); direct.removeFromSuperview(); actions.removeFromSuperview() }
    for orientation in [UIInterfaceOrientation.portrait, .landscapeRight, .portrait, .landscapeLeft, .portrait] {
      try await rotateMapScene(scene, window: window, map: map, to: orientation)
      try assertSceneTripLayout(direct, in: map.view, orientation: orientation)
      try sceneScreenshot(window, name: "direct-trip-\(orientation.rawValue)")
    }
  }

  @MainActor
  func testRealSearchKeyboardKeepsBothCoordinateRowsReachableAcrossSceneRotation() async throws {
    let (map, window, scene) = try await attachedMapScene()
    let manager = map.searchManager
    defer { manager.close(); map.view.endEditing(true) }
    for orientation in [UIInterfaceOrientation.landscapeRight, .portrait, .landscapeLeft, .portrait] {
      try await rotateMapScene(scene, window: window, map: map, to: orientation)
      // Search focuses its native search field automatically. Observe that
      // keyboard before switching input type; equal-height keyboards need not
      // emit a second frame change when the coordinate field becomes first responder.
      var keyboardFrame: CGRect?
      let token = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidChangeFrameNotification,
                                                        object: nil, queue: .main) { notification in
        keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
      }
      defer { NotificationCenter.default.removeObserver(token) }
      manager.startSearching(isRouting: false)
      try await sceneWait("Global search must attach to the real map") {
        manager.viewController?.parent === map && manager.viewController?.viewIfLoaded?.window === window
      }
      let search = try XCTUnwrap(manager.viewController)
      await settleMapScene(map)
      let latitude = try XCTUnwrap(try sceneElement("search.coordinates.mikshat_lat_degrees", in: search.view) as? UITextField)
      let longitude = try XCTUnwrap(try sceneElement("search.coordinates.mikshat_lon_degrees", in: search.view) as? UITextField)
      let coordinateScroll = try XCTUnwrap(try sceneElement("search.coordinateScroll", in: search.view) as? UIScrollView)
      let coordinateInput = try sceneElement("search.coordinateInput", in: search.view)
      XCTAssertTrue(latitude.becomeFirstResponder())
      try await sceneWait("The real coordinate keyboard must be visible") {
        latitude.isFirstResponder && keyboardFrame.map { $0.minY < window.bounds.maxY } == true
      }
      await settleMapScene(map)
      if orientation.isLandscape && UIDevice.current.userInterfaceIdiom == .phone {
        let latitudeRow = try sceneElement("search.coordinates.latitudeRow", in: search.view)
        let longitudeRow = try sceneElement("search.coordinates.longitudeRow", in: search.view)
        XCTAssertEqual(latitudeRow.convert(latitudeRow.bounds, to: window).midY,
                       longitudeRow.convert(longitudeRow.bounds, to: window).midY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(search.availableAreaView.bounds.width,
                                   min(600, search.view.safeAreaLayoutGuide.layoutFrame.width - 16) - 1)
      }
      for field in [latitude, longitude] {
        XCTAssertTrue(field.becomeFirstResponder())
        await settleMapScene(map)
        print("Mikshat real-search field=\(field.accessibilityIdentifier ?? "") orientation=\(orientation.rawValue)"
          + " fieldRect=\(field.convert(field.bounds, to: window)) window=\(window.bounds)"
          + " sheet=\(search.availableAreaView.frame) searchView=\(search.view.bounds) safe=\(search.view.safeAreaLayoutGuide.layoutFrame)"
          + " coordinateScroll=\(coordinateScroll.convert(coordinateScroll.bounds, to: window))"
          + " scrollBounds=\(coordinateScroll.bounds) contentSize=\(coordinateScroll.contentSize)"
          + " offset=\(coordinateScroll.contentOffset) insets=\(coordinateScroll.adjustedContentInset)"
          + " input=\(coordinateInput.frame) keyboardScreen=\(String(describing: keyboardFrame))")
        assertSceneVisible(field, in: window, context: "focused coordinate field")
        let rect = field.convert(field.bounds, to: window)
        let keyboard = try XCTUnwrap(keyboardFrame)
        let keyboardInWindow = window.screen.coordinateSpace.convert(keyboard, to: window)
        XCTAssertLessThanOrEqual(rect.maxY, keyboardInWindow.minY + 1,
                                 "The focused coordinate field must remain above the actual keyboard")
      }
      if orientation.isLandscape && UIDevice.current.userInterfaceIdiom == .phone {
        let keyboard = window.screen.coordinateSpace.convert(try XCTUnwrap(keyboardFrame), to: window)
        for identifier in ["search.coordinates.latitudeRow", "search.coordinates.longitudeRow",
                           "search.coordinates.latitudeDirection", "search.coordinates.longitudeDirection",
                           "search.coordinates.showMap"] {
          let element = try sceneElement(identifier, in: search.view)
          assertSceneVisible(element, in: window, context: identifier)
          XCTAssertLessThanOrEqual(element.convert(element.bounds, to: window).maxY, keyboard.minY + 1)
        }
      }
      try sceneScreenshot(window, name: "search-keyboard-\(orientation.rawValue)")
      map.view.endEditing(true)
      manager.close()
      await settleMapScene(map)
      XCTAssertNil(manager.viewController)
    }
  }
}

@MainActor
@available(iOS 16.0, *)
private func attachedMapScene() async throws -> (MapViewController, UIWindow, UIWindowScene) {
  let map = try XCTUnwrap(MapViewController.shared())
  map.loadViewIfNeeded()
  map.searchManager.close()
  map.dismissPlacePage()
  MWMNavigationDashboardManager.shared().onRouteStop()
  if map.presentedViewController != nil { map.dismiss(animated: false) }
  let window = try XCTUnwrap(MapsAppDelegate.theApp().window)
  window.makeKeyAndVisible()
  let scene = try XCTUnwrap(window.windowScene)
  try await sceneWait("The actual map scene must be foreground and attached") {
    map.view.window === window && window.isKeyWindow && !window.isHidden
      && UIApplication.shared.applicationState == .active
  }
  map.view.semanticContentAttribute = .forceRightToLeft
  try await rotateMapScene(scene, window: window, map: map, to: .portrait)
  return (map, window, scene)
}

@MainActor
@available(iOS 16.0, *)
private func rotateMapScene(_ scene: UIWindowScene, window: UIWindow, map: MapViewController,
                            to orientation: UIInterfaceOrientation) async throws {
  func actualGeometryMatches() -> Bool {
    scene.interfaceOrientation == orientation
      && (orientation.isLandscape ? window.bounds.width > window.bounds.height : window.bounds.height > window.bounds.width)
      && abs(map.view.bounds.width - window.bounds.width) < 1
      && abs(map.view.bounds.height - window.bounds.height) < 1
  }
  var geometryError: Error?
  print("Mikshat real-scene rotation requested=\(orientation.rawValue) actual=\(scene.interfaceOrientation.rawValue)"
        + " window=\(window.bounds) map=\(map.view.bounds) alreadyMatches=\(actualGeometryMatches())")
  if UIDevice.current.userInterfaceIdiom == .pad {
    // A multitasking iPad app may reject programmatic scene rotation even in
    // Full Screen Apps mode. CI instead rotates the actual simulated device
    // through the public CLI, previously verified against native screen pixels.
    if !actualGeometryMatches() {
      try await requestPhysicalSceneRotation(to: orientation)
    }
  } else {
    let mask: UIInterfaceOrientationMask = orientation == .portrait ? .portrait
      : (orientation == .landscapeLeft ? .landscapeLeft : .landscapeRight)
    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) {
      geometryError = $0
      print("Mikshat real-scene geometry request failed: \($0)")
    }
  }
  try await sceneWait("UIKit must perform the requested real scene rotation") {
    actualGeometryMatches()
  }
  if let geometryError { throw geometryError }
  await settleMapScene(map)
}

@MainActor
private func requestPhysicalSceneRotation(to orientation: UIInterfaceOrientation) async throws {
  let directory = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
  let prefix = "mikshat-scene-rotation-"
  func read(_ name: String) -> [String: Any]? {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent(prefix + name + ".json")) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
  var ready: [String: Any]?
  try await sceneWait("The isolated iPad must have a ready public physical-rotation driver") {
    ready = read("ready")
    guard ready?["version"] as? Int == 1, ready?["driver"] as? String == "devicectl",
          let session = ready?["session"] as? String, UUID(uuidString: session) != nil,
          let heartbeat = ready?["heartbeatAt"] as? Double else { return false }
    return abs(Date().timeIntervalSince1970 - heartbeat) < 15
  }
  let session = try XCTUnwrap(ready?["session"] as? String)
  let identifier = UUID().uuidString
  // Physical and interface landscape names are opposites in UIKit.
  let physical: String
  switch orientation {
  case .portrait: physical = "portrait"
  case .portraitUpsideDown: physical = "portraitUpsideDown"
  case .landscapeLeft: physical = "landscapeRight"
  case .landscapeRight: physical = "landscapeLeft"
  default: throw NSError(domain: "MikshatSceneRotation", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported test orientation"])
  }
  let request: [String: Any] = ["version": 1, "session": session, "id": identifier,
                               "physicalOrientation": physical, "interfaceOrientation": orientation.rawValue]
  let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
  try data.write(to: directory.appendingPathComponent(prefix + "request.json"), options: .atomic)
  print("Mikshat public physical rotation requested id=\(identifier) documents=\(directory.path)"
        + " createdAt=\(Date().timeIntervalSince1970) physical=\(physical) interface=\(orientation.rawValue)")
  var response: [String: Any]?
  let deadline = Date().addingTimeInterval(30)
  repeat {
    response = read("response")
    if response?["version"] as? Int == 1, response?["session"] as? String == session,
       response?["id"] as? String == identifier { break }
    try await Task.sleep(nanoseconds: 50_000_000)
  } while Date() < deadline
  guard response?["version"] as? Int == 1, response?["id"] as? String == identifier,
        response?["session"] as? String == session,
        response?["success"] as? Bool == true, response?["physicalOrientation"] as? String == physical else {
    XCTFail("The public physical-rotation command failed or timed out: \(String(describing: response))")
    throw NSError(domain: "MikshatSceneRotation", code: 2,
                  userInfo: [NSLocalizedDescriptionKey: "The physical iPad rotation driver did not acknowledge success"])
  }
  print("Mikshat public physical rotation acknowledged id=\(identifier) physical=\(physical) interface=\(orientation.rawValue)")
  // The caller still requires actual scene orientation plus window/map aspect
  // and dimensions. An acknowledged CLI command alone never passes the test.
}

@MainActor
private func sceneWait(_ description: String, condition: () -> Bool) async throws {
  let deadline = Date().addingTimeInterval(12)
  while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
  guard condition() else {
    XCTFail(description)
    throw NSError(domain: "MikshatMapSceneLayoutTests", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: description])
  }
}

@MainActor
private func settleMapScene(_ map: MapViewController) async {
  for _ in 0..<8 {
    map.view.setNeedsLayout()
    map.view.layoutIfNeeded()
    map.view.window?.layoutIfNeeded()
    try? await Task.sleep(nanoseconds: 50_000_000)
  }
}

@MainActor
private func sceneElement(_ identifier: String, in root: UIView) throws -> UIView {
  try XCTUnwrap(presentationDescendants(root).first { $0.accessibilityIdentifier == identifier },
                "Missing actual scene element: \(identifier)")
}

@MainActor
private func assertSceneVisible(_ element: UIView, in viewport: UIView, context: String,
                                file: StaticString = #filePath, line: UInt = #line) {
  let rect = element.convert(element.bounds, to: viewport)
  let expectedWindow = (viewport as? UIWindow) ?? viewport.window
  let details = "\(context); id=\(element.accessibilityIdentifier ?? String(describing: type(of: element)))"
    + " rect=\(rect) viewportBounds=\(viewport.bounds) viewportSafe=\(viewport.safeAreaInsets)"
    + " expectedWindow=\(String(describing: expectedWindow)) actualWindow=\(String(describing: element.window))"
    + " orientation=\(expectedWindow?.windowScene?.interfaceOrientation.rawValue ?? 0)"
  var ancestor: UIView? = element
  while let view = ancestor {
    XCTAssertFalse(view.isHidden || view.alpha < 0.01, details, file: file, line: line)
    if view === viewport { break }
    ancestor = view.superview
  }
  XCTAssertTrue(element.window === expectedWindow || element === viewport, "Window mismatch: " + details, file: file, line: line)
  XCTAssertGreaterThan(rect.width, 0, details, file: file, line: line)
  XCTAssertGreaterThan(rect.height, 0, details, file: file, line: line)
  XCTAssertTrue(viewport.bounds.insetBy(dx: -1, dy: -1).contains(rect), "Outside viewport: " + details, file: file, line: line)
}

@MainActor
private func assertSceneTripLayout(_ card: UIView, in map: UIView, orientation: UIInterfaceOrientation) throws {
  let safe = map.safeAreaLayoutGuide.layoutFrame
  let cardRect = card.convert(card.bounds, to: map)
  XCTAssertEqual(cardRect.maxY, safe.maxY, accuracy: 1)
  XCTAssertGreaterThanOrEqual(cardRect.minX, safe.minX - 1)
  XCTAssertLessThanOrEqual(cardRect.maxX, safe.maxX + 1)
  assertSceneVisible(card, in: map, context: "actual bottom trip card")
  let tools = try XCTUnwrap(try sceneElement("navigation.mapActions", in: map) as? UIStackView)
  let toolsRect = tools.convert(tools.bounds, to: map)
  assertSceneVisible(tools, in: map, context: "search/favorites/record tools")
  XCTAssertFalse(toolsRect.intersects(cardRect))
  if !orientation.isLandscape {
    XCTAssertEqual(tools.axis, .vertical)
    XCTAssertLessThanOrEqual(toolsRect.maxY, cardRect.minY - 1,
                             "Returning to portrait must restore the tools above the card")
    XCTAssertLessThan(toolsRect.minX, safe.minX + 100)
  }
  let controls = try ["map.speedCard", "map.compass", "map.qibla", "map.zoomIn", "map.zoomOut", "map.location"]
    .map { try sceneElement($0, in: map) }
  for (index, control) in controls.enumerated() {
    assertSceneVisible(control, in: map, context: control.accessibilityIdentifier ?? "map control")
    let rect = control.convert(control.bounds, to: map)
    XCTAssertFalse(rect.intersects(cardRect), "A right-side control overlaps the bottom trip card")
    for other in controls.dropFirst(index + 1) {
      XCTAssertFalse(rect.intersects(other.convert(other.bounds, to: map)), "Right-side controls overlap")
    }
  }
}

@MainActor
private func sceneNavigationEntity() -> MWMNavigationDashboardEntity {
  let info = MWMNavigationDashboardEntity()
  for (key, value) in [("streetName", "طريق الموقع المحدد"), ("distanceToTurn", "250"),
                        ("turnUnits", "م"), ("targetDistance", "3.6"), ("targetUnits", "كم")] {
    info.setValue(value, forKey: key)
  }
  info.setValue(420, forKey: "timeToTarget")
  info.setValue(UIImage(systemName: "arrow.turn.up.left"), forKey: "turnImage")
  info.setValue(UIImage(systemName: "arrow.turn.up.right"), forKey: "nextTurnImage")
  return info
}

@MainActor
@available(iOS 16.0, *)
private func assertActualWeatherSheet(in map: MapViewController, window: UIWindow, scene: UIWindowScene) async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MikshatSceneWeather-" + UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let repository = MikshatWeatherRepository(cacheDirectory: directory, client: WeatherFixtureClient())
  let coordinate = MikshatWeatherCoordinate(latitude: 24.65, longitude: 46.71)
  _ = try await repository.refresh(for: coordinate, force: true)
  let weather = MikshatWeatherViewController(name: "نقطة الخريطة", latitude: coordinate.latitude,
                                            longitude: coordinate.longitude, repository: repository)
  map.present(weather, animated: false)
  defer { map.dismiss(animated: false) }
  try await sceneWait("Synthetic weather must render inside the actual presented sheet") {
    guard weather.viewIfLoaded?.window === window,
          let current = presentationDescendants(weather.view).first(where: { $0.accessibilityIdentifier == "weather.current" }),
          let refresh = presentationDescendants(weather.view).first(where: { $0.accessibilityIdentifier == "weather.refresh" }) as? UIButton
    else { return false }
    return !current.isHidden && refresh.isEnabled
  }
  for orientation in [UIInterfaceOrientation.portrait, .landscapeRight, .portrait] {
    try await rotateMapScene(scene, window: window, map: map, to: orientation)
    let sheet = try XCTUnwrap(weather.sheetPresentationController)
    let page = try XCTUnwrap(try sceneElement("weather.scroll", in: weather.view) as? UIScrollView)
    let content = try sceneElement("weather.content", in: weather.view)
    let location = try sceneElement("weather.location", in: weather.view)
    let title = try sceneElement("weather.title", in: weather.view)
    let portraitPhone = UIDevice.current.userInterfaceIdiom == .phone && !orientation.isLandscape
    XCTAssertEqual(sheet.detents.count, 1)
    XCTAssertEqual(sheet.selectedDetentIdentifier?.rawValue,
                   portraitPhone ? "mikshat.weather.content" : UISheetPresentationController.Detent.Identifier.large.rawValue)
    page.setContentOffset(.zero, animated: false)
    await settleMapScene(map)
    if portraitPhone {
      let rect = weather.view.convert(weather.view.bounds, to: window)
      XCTAssertGreaterThan(rect.minY, window.safeAreaInsets.top + 80,
                           "The actual portrait page sheet must move down instead of remaining nearly full height")
      XCTAssertLessThan(weather.preferredContentSize.height, window.bounds.height - 100)
      XCTAssertLessThanOrEqual(window.bounds.maxY - rect.maxY, window.safeAreaInsets.bottom + 16)
      XCTAssertEqual(content.convert(content.bounds, to: page).minY, 4, accuracy: 1)
      let titleRect = title.convert(title.bounds, to: weather.view)
      let locationRect = location.convert(location.bounds, to: weather.view)
      XCTAssertLessThan(locationRect.minY - titleRect.maxY, 64,
                        "There must not be a large empty gap between the sheet heading and selected location")
    }
    for identifier in ["weather.title", "weather.close", "weather.location", "weather.current"] {
      assertSceneVisible(try sceneElement(identifier, in: weather.view), in: window, context: "actual weather sheet")
    }
    for identifier in ["weather.refresh", "weather.notice", "weather.attribution"] {
      let element = try sceneElement(identifier, in: weather.view)
      page.scrollRectToVisible(element.convert(element.bounds, to: page), animated: false)
      await settleMapScene(map)
      assertSceneVisible(element, in: page, context: "weather footer inside the actual scroll viewport")
      assertSceneVisible(element, in: window, context: "reachable weather footer")
    }
    page.setContentOffset(.zero, animated: false)
    await settleMapScene(map)
    try sceneScreenshot(window, name: "weather-sheet-\(orientation.rawValue)")
  }
}

@MainActor
private func sceneScreenshot(_ window: UIWindow, name: String) throws {
  let format = UIGraphicsImageRendererFormat()
  format.scale = 1
  let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { window.layer.render(in: $0.cgContext) }
  let data = try XCTUnwrap(image.pngData())
  let directory = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try data.write(to: directory.appendingPathComponent("responsive-real-scene-\(name).png"), options: .atomic)
  let attachment = XCTAttachment(image: image)
  attachment.name = "responsive-real-scene-\(name)"
  attachment.lifetime = .keepAlways
  XCTContext.runActivity(named: "responsive-real-scene-\(name)") { $0.add(attachment) }
  print("Mikshat real-scene screenshot=\(name) orientation=\(window.windowScene?.interfaceOrientation.rawValue ?? 0) bounds=\(window.bounds) safeInsets=\(window.safeAreaInsets)")
}

private let presentationViewports: [(String, CGSize)] = [
  ("compact-phone", CGSize(width: 320, height: 568)),
  ("large-phone", CGSize(width: 430, height: 932)),
  ("ipad", CGSize(width: 768, height: 1024)),
]

@MainActor
private func presentationDescendants(_ root: UIView) -> [UIView] {
  [root] + root.subviews.flatMap { presentationDescendants($0) }
}

@MainActor
private func presentationElement(_ identifier: String, in root: UIView,
                                 file: StaticString = #filePath, line: UInt = #line) throws -> UIView {
  try XCTUnwrap(presentationDescendants(root).first { $0.accessibilityIdentifier == identifier }, file: file, line: line)
}

private func assertHorizontallyContained(_ rect: CGRect, in container: CGRect,
                                         file: StaticString = #filePath, line: UInt = #line) {
  XCTAssertGreaterThan(rect.width, 0, file: file, line: line)
  XCTAssertGreaterThanOrEqual(rect.minX, container.minX - 1, file: file, line: line)
  XCTAssertLessThanOrEqual(rect.maxX, container.maxX + 1, file: file, line: line)
}

@MainActor
private final class PresentationUIKitHost {
  let window: UIWindow
  let container = UIViewController()
  let controller: UIViewController
  private let canvas = UIViewController()

  init(_ controller: UIViewController, size: CGSize) {
    self.controller = controller
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .filter { $0.session.role == .windowApplication && $0.activationState != .background && $0.activationState != .unattached }
    if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
      window = UIWindow(windowScene: scene)
    } else {
      window = UIWindow(frame: CGRect(origin: .zero, size: ResponsiveFixtureViewport.canvasSize(for: size)))
    }
    window.frame = CGRect(origin: .zero, size: ResponsiveFixtureViewport.canvasSize(for: size))
    window.overrideUserInterfaceStyle = .light
    canvas.loadViewIfNeeded()
    canvas.view.frame = window.bounds
    canvas.addChild(container)
    container.loadViewIfNeeded()
    container.view.autoresizingMask = []
    container.view.frame = CGRect(origin: CGPoint(x: ResponsiveFixtureViewport.margin, y: ResponsiveFixtureViewport.margin),
                                  size: size)
    container.view.backgroundColor = .systemBackground
    canvas.view.addSubview(container.view)
    container.didMove(toParent: canvas)
    if controller.parent != nil {
      controller.willMove(toParent: nil)
      controller.view.removeFromSuperview()
      controller.removeFromParent()
    }
    container.addChild(controller)
    controller.view.frame = container.view.bounds
    controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    controller.view.semanticContentAttribute = .forceRightToLeft
    container.view.addSubview(controller.view)
    controller.didMove(toParent: container)
    window.rootViewController = canvas
    window.isHidden = false
    resize(size)
  }

  func resize(_ size: CGSize) {
    window.frame = CGRect(origin: .zero, size: ResponsiveFixtureViewport.canvasSize(for: size))
    container.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
      UITraitCollection(layoutDirection: .rightToLeft), UITraitCollection(preferredContentSizeCategory: .large),
      UITraitCollection(horizontalSizeClass: size.width >= 600 ? .regular : .compact),
      UITraitCollection(verticalSizeClass: size.height < 500 ? .compact : .regular),
    ]), forChild: controller)
    canvas.view.frame = window.bounds
    container.view.frame = CGRect(origin: CGPoint(x: ResponsiveFixtureViewport.margin, y: ResponsiveFixtureViewport.margin),
                                  size: size)
    let profile = ResponsiveFixtureViewport.insets(for: size)
    let expected = UIEdgeInsets(top: profile.top, left: profile.left + 27, bottom: profile.bottom, right: profile.right + 9)
    controller.additionalSafeAreaInsets = expected
    controller.view.frame = container.view.bounds
    for _ in 0..<4 {
      canvas.view.setNeedsLayout()
      container.view.setNeedsLayout()
      controller.view.setNeedsLayout()
      canvas.view.layoutIfNeeded()
      container.view.layoutIfNeeded()
      controller.view.layoutIfNeeded()
    }
    XCTAssertEqual(container.view.bounds.width, size.width, accuracy: 1)
    XCTAssertEqual(container.view.bounds.height, size.height, accuracy: 1)
    XCTAssertEqual(container.view.frame.minX, ResponsiveFixtureViewport.margin, accuracy: 1)
    XCTAssertEqual(container.view.frame.minY, ResponsiveFixtureViewport.margin, accuracy: 1)
    XCTAssertEqual(controller.view.bounds.width, size.width, accuracy: 1)
    XCTAssertEqual(controller.view.bounds.height, size.height, accuracy: 1)
    ResponsiveFixtureViewport.assertInsets(of: container.view, equalTo: .zero)
    ResponsiveFixtureViewport.assertInsets(of: controller.view, equalTo: expected)
  }

  func close() {
    window.isHidden = true
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
    container.willMove(toParent: nil)
    container.view.removeFromSuperview()
    container.removeFromParent()
    window.rootViewController = nil
  }
}

private final class PresentationMenuRows: NSObject, BottomMenuPresenterProtocol {
  private let items: [(UIImage, String)] = [
    (UIImage(resource: .icMenuAddPlace), L("placepage_add_place_button")),
    (UIImage(resource: .icMenuTrackRecording), L("start_track_recording")),
    (UIImage(resource: .icMenuDownload), L("download_maps")),
    (UIImage(resource: .icMenuDonate), L("donate")),
    (UIImage(resource: .icMenuSettings), L("settings")),
    (UIImage(resource: .icMenuShare), L("share_my_location")),
  ]

  func onClosePressed() {}
  func cellToHighlightIndexPath() -> IndexPath? { nil }
  func numberOfSections(in tableView: UITableView) -> Int { 2 }
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    section == 0 ? 1 : items.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if indexPath.section == 0 {
      let cell = tableView.dequeueReusableCell(cell: BottomMenuLayersCell.self)!
      cell.addSeparator(.bottom)
      return cell
    }
    let cell = tableView.dequeueReusableCell(cell: BottomMenuItemCell.self)!
    let (image, title) = items[indexPath.row]
    cell.configure(image: image, title: title)
    return cell
  }
}
