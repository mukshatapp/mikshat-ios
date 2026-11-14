@testable import Organic_Maps__Debug_
import XCTest
import UIKit

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
        let bounded = UIDevice.current.userInterfaceIdiom == .pad || search.traitCollection.verticalSizeClass == .compact
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
    let map = try XCTUnwrap(MapViewController.shared())
    map.loadViewIfNeeded()
    let controls = try XCTUnwrap(MWMMapViewControlsManager.manager())
    let delegate = PresentationMenuDelegate()
    for (name, portrait) in presentationViewports {
      let menu = try XCTUnwrap(BottomMenuBuilder.buildMenu(mapViewController: map, controlsManager: controls,
                                                         delegate: delegate) as? BottomMenuViewController)
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
        XCTAssertGreaterThan(menu.tableView.numberOfSections, 0)
        XCTAssertGreaterThan(menu.tableView.numberOfRows(inSection: 0), 0)
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

  init(_ controller: UIViewController, size: CGSize) {
    self.controller = controller
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .filter { $0.session.role == .windowApplication && $0.activationState != .background && $0.activationState != .unattached }
    if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
      window = UIWindow(windowScene: scene)
    } else {
      window = UIWindow(frame: CGRect(origin: .zero, size: size))
    }
    window.frame = CGRect(origin: .zero, size: size)
    window.overrideUserInterfaceStyle = .light
    container.loadViewIfNeeded()
    container.view.frame = window.bounds
    container.view.backgroundColor = .systemBackground
    if controller.parent != nil {
      controller.willMove(toParent: nil)
      controller.view.removeFromSuperview()
      controller.removeFromParent()
    }
    container.addChild(controller)
    controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 27, bottom: 0, right: 9)
    controller.view.frame = container.view.bounds
    controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    controller.view.semanticContentAttribute = .forceRightToLeft
    container.view.addSubview(controller.view)
    controller.didMove(toParent: container)
    window.rootViewController = container
    window.isHidden = false
    resize(size)
  }

  func resize(_ size: CGSize) {
    window.frame = CGRect(origin: .zero, size: size)
    container.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
      UITraitCollection(layoutDirection: .rightToLeft), UITraitCollection(preferredContentSizeCategory: .large),
      UITraitCollection(horizontalSizeClass: size.width >= 600 ? .regular : .compact),
      UITraitCollection(verticalSizeClass: size.height < 500 ? .compact : .regular),
    ]), forChild: controller)
    container.view.frame = window.bounds
    controller.view.frame = container.view.bounds
    for _ in 0..<4 {
      container.view.setNeedsLayout()
      controller.view.setNeedsLayout()
      container.view.layoutIfNeeded()
      controller.view.layoutIfNeeded()
    }
  }

  func close() {
    window.isHidden = true
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
    window.rootViewController = nil
  }
}

private final class PresentationMenuDelegate: NSObject, BottomMenuDelegate {
  func actionDownloadMaps(_ mode: MWMMapDownloaderMode) {}
  func addPlace() {}
  func didFinishAddingPlace() {}
}
