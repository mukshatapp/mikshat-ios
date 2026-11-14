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
