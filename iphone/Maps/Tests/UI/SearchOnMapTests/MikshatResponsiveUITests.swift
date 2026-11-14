@testable import Organic_Maps__Debug_
import XCTest
import UIKit
import CoreLocation

final class MikshatResponsiveCompassTests: XCTestCase {
  @MainActor
  func testCompassContentFitsPhonesAndTabletAfterRotatingTheSameContainer() throws {
    for general in [false, true] {
      for (device, portrait) in responsivePortraitSizes {
        let compass = MikshatCompassViewController(target: general ? nil : responsiveDestination,
                                                   name: "الموقع المحدد على الخريطة", general: general)
        let host = ResponsiveUIKitHost(compass, size: portrait)
        defer { host.close() }
        for (orientation, size) in [("portrait", portrait), ("landscape", portrait.rotated)] {
          host.resize(size)
          compass.updateReadings(position: responsiveLocation(), reading: (degrees: 72, gps: false))
          host.layout()
          let scroll = try responsiveElement("mikshat.compass.scroll", in: compass.view, as: UIScrollView.self)
          let dial = try responsiveElement("mikshat.compass.dial", in: compass.view)
          let coordinates = try responsiveElement("mikshat.compass.coordinates", in: compass.view, as: UILabel.self)
          XCTAssertLessThanOrEqual(scroll.contentSize.height, scroll.bounds.height + 1,
                                   "All normal compass content must fit \(device) \(orientation), general=\(general)")
          XCTAssertGreaterThan(dial.bounds.width, 80)
          XCTAssertEqual(dial.bounds.width, dial.bounds.height, accuracy: 1)
          XCTAssertTrue(dial.isAccessibilityElement)
          XCTAssertFalse((dial.accessibilityValue ?? "").isEmpty)
          var visible = ["title", "close", "dial", "coordinates", "copy", "speed", "status"]
          visible += general ? ["save"] : ["distance", "duration", "arrival"]
          for suffix in visible {
            assertResponsiveVisible(try responsiveElement("mikshat.compass." + suffix, in: compass.view),
                                    in: scroll, context: "\(device) \(orientation)")
          }
          XCTAssertFalse(dial.convert(dial.bounds, to: scroll).intersects(coordinates.convert(coordinates.bounds, to: scroll)))
          XCTAssertEqual(coordinates.text, responsiveCoordinateText["ddm"])
          assertResponsiveLabelFits(coordinates)
          try attachResponsiveScreenshot(host.container.view,
                                         name: "compass-\(general ? "general" : "destination")-\(device)-\(orientation)",
                                         test: self)
        }
      }
    }
  }

  @MainActor
  func testCurrentCoordinatePairAndGreenCopyActionRemainReadableWithoutGPS() throws {
    let compass = MikshatCompassViewController(target: nil, name: "البوصلة", general: true)
    let host = ResponsiveUIKitHost(compass, size: CGSize(width: 320, height: 568))
    defer { host.close() }
    compass.updateReadings(position: responsiveLocation(), reading: (degrees: 135, gps: false))
    host.layout()
    let coordinates = try responsiveElement("mikshat.compass.coordinates", in: compass.view, as: UILabel.self)
    let copy = try responsiveElement("mikshat.compass.copy", in: compass.view, as: UIButton.self)
    XCTAssertEqual(coordinates.text?.components(separatedBy: "\n"), ["N 24° 39.001′", "E 046° 42.601′"])
    assertResponsiveLabelFits(coordinates)
    XCTAssertEqual(copy.configuration?.baseBackgroundColor?.resolvedColor(with: compass.traitCollection),
                   MikshatStyle.green.resolvedColor(with: compass.traitCollection))
    XCTAssertEqual(copy.configuration?.baseForegroundColor, .white)
    XCTAssertFalse((copy.accessibilityLabel ?? "").isEmpty)
    XCTAssertGreaterThanOrEqual(copy.bounds.width, 44)
    XCTAssertGreaterThanOrEqual(copy.bounds.height, 44)

    // Losing position must keep a usable sensor compass, while disabling actions that need a position.
    compass.updateReadings(position: nil, reading: (degrees: 135, gps: false))
    host.layout()
    XCTAssertEqual(coordinates.text, "—")
    XCTAssertFalse(copy.isEnabled)
    XCTAssertEqual(try responsiveElement("mikshat.compass.dial", in: compass.view).accessibilityValue, "135°")
    XCTAssertFalse(try responsiveElement("mikshat.compass.save", in: compass.view, as: UIButton.self).isEnabled)
  }

  @MainActor
  func testAccessibilityTypeCanReachFullCoordinatePairAndCopyAction() throws {
    for (device, size) in [("compact-phone", CGSize(width: 320, height: 568)),
                           ("tablet-landscape", CGSize(width: 1024, height: 768))] {
      let compass = MikshatCompassViewController(target: responsiveDestination, name: "الموقع المحدد على الخريطة")
      let host = ResponsiveUIKitHost(compass, size: size, category: .accessibilityExtraExtraExtraLarge)
      defer { host.close() }
      compass.updateReadings(position: responsiveLocation(), reading: (degrees: 72, gps: false))
      host.layout()
      let scroll = try responsiveElement("mikshat.compass.scroll", in: compass.view, as: UIScrollView.self)
      let copy = try responsiveElement("mikshat.compass.copy", in: compass.view, as: UIButton.self)
      let coordinates = try responsiveElement("mikshat.compass.coordinates", in: compass.view, as: UILabel.self)
      XCTAssertEqual(compass.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
      XCTAssertTrue(scroll.isScrollEnabled)
      XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
      XCTAssertFalse(scroll.hasAmbiguousLayout)
      XCTAssertEqual(coordinates.text, responsiveCoordinateText["ddm"])
      assertResponsiveLabelFits(coordinates)
      XCTAssertGreaterThanOrEqual(copy.bounds.height, 44)
      let actionRect = copy.convert(copy.bounds, to: scroll)
      scroll.scrollRectToVisible(actionRect, animated: false)
      host.layout()
      assertResponsiveVisible(copy, in: scroll, context: device)
      try attachResponsiveScreenshot(host.container.view, name: "compass-accessibility-\(device)", test: self)
    }
  }
}

final class MikshatResponsivePlaceCoordinatesTests: XCTestCase {
  @MainActor
  func testInlineFormatsCopyTheSelectedPointAndReturnToTheirCollapsedHeight() throws {
    for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
      var copies: [String] = []
      var expansionChanges = 0
      let coordinates = PlacePageCoordinatesView(coordinate: responsiveSelectedPoint,
                                                 copy: { copies.append($0) },
                                                 didChangeExpanded: { expansionChanges += 1 })
      let controller = ResponsiveContentController(content: coordinates)
      let host = ResponsiveUIKitHost(controller, size: CGSize(width: 320, height: 568), category: category)
      defer { host.close() }
      let toggle = try responsiveElement("placePage.coordinates.toggle", in: coordinates, as: UIButton.self)
      let collapsedHeight = coordinates.bounds.height
      XCTAssertGreaterThan(collapsedHeight, 0)
      XCTAssertFalse(coordinates.isExpanded)
      XCTAssertEqual(toggle.accessibilityValue, L("mikshat_collapsed"))
      XCTAssertNil(responsiveDescendants(coordinates).first { $0.accessibilityIdentifier == "placePage.coordinates.dd" })
      XCTAssertNil(responsiveDescendants(coordinates).first { $0.accessibilityIdentifier == "placePage.coordinates.dms" })
      try assertSelectedCoordinateRow("ddm", in: coordinates)
      try responsiveElement("placePage.coordinates.ddm.copy", in: coordinates, as: UIButton.self).sendActions(for: .touchUpInside)

      toggle.sendActions(for: .touchUpInside)
      host.layout()
      XCTAssertTrue(coordinates.isExpanded)
      XCTAssertTrue(toggle.isSelected)
      XCTAssertEqual(toggle.accessibilityValue, L("mikshat_expanded"))
      XCTAssertEqual(expansionChanges, 1)
      XCTAssertGreaterThan(coordinates.bounds.height, collapsedHeight)
      for format in ["dd", "dms"] {
        try assertSelectedCoordinateRow(format, in: coordinates)
        try responsiveElement("placePage.coordinates.\(format).copy", in: coordinates, as: UIButton.self)
          .sendActions(for: .touchUpInside)
      }
      XCTAssertEqual(copies, [responsiveCoordinateText["ddm"]!, responsiveCoordinateText["dd"]!, responsiveCoordinateText["dms"]!])
      XCTAssertNil(controller.presentedViewController, "Formats must expand inside the place card")
      try attachResponsiveScreenshot(host.container.view, name: "place-formats-\(category.rawValue)", test: self)
      toggle.sendActions(for: .touchUpInside)
      host.layout()
      XCTAssertFalse(coordinates.isExpanded)
      XCTAssertFalse(toggle.isSelected)
      XCTAssertEqual(expansionChanges, 2)
      XCTAssertEqual(coordinates.bounds.height, collapsedHeight, accuracy: 1)
    }
  }

  @MainActor
  func testPreviewInlineExpansionRefreshesHeightAndCopiesTheSelectedMapPoint() throws {
    for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
      let data = ResponsivePlacePreviewData()
      let delegate = ResponsivePlacePreviewDelegate()
      let preview = UIStoryboard.instance(.placePage).instantiateViewController(ofType: PlacePagePreviewViewController.self)
      preview.placePagePreviewData = data
      preview.mikshatCoordinate = responsiveSelectedPoint
      preview.delegate = delegate
      let host = ResponsiveUIKitHost(preview, size: CGSize(width: 320, height: 568), category: category, fitContentHeight: true)
      defer { host.close() }
      for (device, size) in [("phone-portrait", CGSize(width: 320, height: 568)),
                             ("phone-landscape", CGSize(width: 568, height: 320)),
                             ("tablet-portrait", CGSize(width: 768, height: 1024)),
                             ("tablet-landscape", CGSize(width: 1024, height: 768))] {
        host.resize(size)
        let coordinates = try responsiveElement("placePage.coordinates", in: preview.view, as: PlacePageCoordinatesView.self)
        let toggle = try responsiveElement("placePage.coordinates.toggle", in: preview.view, as: UIButton.self)
        let collapsedHeight = preview.view.bounds.height
        XCTAssertFalse(coordinates.isExpanded)
        XCTAssertEqual(responsiveDescendants(preview.view).filter { $0 is PlacePageCoordinatesView }.count, 1)
        toggle.sendActions(for: .touchUpInside)
        host.layout()
        XCTAssertGreaterThan(preview.view.bounds.height, collapsedHeight)
        for format in ["ddm", "dd", "dms"] {
          try assertSelectedCoordinateRow(format, in: coordinates)
          try responsiveElement("placePage.coordinates.\(format).copy", in: coordinates, as: UIButton.self)
            .sendActions(for: .touchUpInside)
          XCTAssertEqual(delegate.copies.last, responsiveCoordinateText[format])
        }
        XCTAssertNil(preview.presentedViewController)
        try attachResponsiveScreenshot(host.container.view,
                                       name: "place-preview-\(device)-\(category.rawValue)", test: self)
        toggle.sendActions(for: .touchUpInside)
        host.layout()
        XCTAssertEqual(preview.view.bounds.height, collapsedHeight, accuracy: 1)
      }
      XCTAssertEqual(delegate.contentSizeChanges, 8)
    }
  }

  @MainActor
  func testInformationEndsWithOneAccessibleWeatherActionAndNoDuplicateCoordinateRows() throws {
    for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
      let data = ResponsivePlaceInfoData()
      let info = UIStoryboard.instance(.placePage).instantiateViewController(ofType: PlacePageInfoViewController.self)
      info.placePageInfoData = data
      var weatherTaps = 0
      info.didTapWeather = { weatherTaps += 1 }
      let host = ResponsiveUIKitHost(info, size: CGSize(width: 320, height: 568), category: category, fitContentHeight: true)
      defer { host.close() }
      for (device, portrait) in responsivePortraitSizes {
        for size in [portrait, portrait.rotated] {
          host.resize(size)
          let weather = try responsiveElement("placePage.weather", in: info.view, as: InfoItemView.self)
          XCTAssertTrue(info.stackView.arrangedSubviews.last === weather)
          XCTAssertTrue(responsiveDescendants(info.view).filter { $0 is MikshatCoordinateRow || $0 is PlacePageCoordinatesView }.isEmpty)
          XCTAssertGreaterThanOrEqual(weather.bounds.height, 44)
          XCTAssertEqual(weather.frame.maxY, info.view.bounds.maxY, accuracy: 1)
          XCTAssertTrue(weather.isAccessibilityElement)
          XCTAssertTrue(weather.accessibilityTraits.contains(.button))
          XCTAssertFalse((weather.accessibilityLabel ?? "").isEmpty)
          assertResponsiveVisible(weather.textLabel, in: weather, context: device)
          weather.infoLabelTapHandler?()
          weather.iconButton.sendActions(for: .touchUpInside)
          weather.accessoryButton.sendActions(for: .touchUpInside)
        }
      }
      XCTAssertEqual(weatherTaps, 24)
      try attachResponsiveScreenshot(host.container.view, name: "place-weather-\(category.rawValue)", test: self)
    }
  }
}

final class MikshatResponsiveNavigationTests: XCTestCase {
  @MainActor
  func testThreeDigitSpeedAndEntireRightControlChainAvoidTheManeuverAfterRotation() throws {
    defer { restoreResponsiveMapControls() }
    for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
      let controller = UIViewController()
      let host = ResponsiveUIKitHost(controller, size: CGSize(width: 320, height: 568), category: category)
      defer { host.close() }
      MikshatHomeControls.install(in: controller.view)
      let native = try XCTUnwrap(MWMSideButtons(parentView: controller.view))
      let maneuver = UIView()
      maneuver.backgroundColor = .systemBlue
      controller.view.addSubview(maneuver)
      for (device, portrait) in responsivePortraitSizes {
        for (orientation, size) in [("portrait", portrait), ("landscape", portrait.rotated)] {
          host.resize(size)
          let safe = controller.view.safeAreaLayoutGuide.layoutFrame
          maneuver.frame = CGRect(x: safe.minX + 8, y: safe.minY + 4, width: safe.width - 16,
                                  height: size.width > size.height ? 72 : 96)
          MikshatHomeControls.updateNavigationObstruction(maneuver, frame: maneuver.bounds)
          host.layout()
          let speed = try responsiveElement("map.speedValue", in: controller.view, as: UILabel.self)
          speed.text = "123"
          host.layout()
          XCTAssertEqual(speed.numberOfLines, 1)
          XCTAssertEqual(speed.text, "123")
          assertResponsiveLabelFits(speed)
          let ids = ["map.speedCard", "map.compass", "map.qibla", "map.zoomIn", "map.zoomOut", "map.location"]
          let controls = try ids.map { try responsiveElement($0, in: controller.view) }
          for control in controls {
            assertResponsiveVisible(control, in: controller.view, context: "\(device) \(orientation)")
            let rect = control.convert(control.bounds, to: controller.view)
            XCTAssertFalse(rect.intersects(maneuver.frame), "\(control.accessibilityIdentifier ?? "control") overlaps maneuver")
            XCTAssertGreaterThanOrEqual(control.bounds.width, 44)
            XCTAssertGreaterThanOrEqual(control.bounds.height, 44)
          }
          for (index, control) in controls.enumerated() {
            for next in controls.dropFirst(index + 1) {
              XCTAssertFalse(control.convert(control.bounds, to: controller.view)
                .intersects(next.convert(next.bounds, to: controller.view)), "Map controls overlap after reflow")
            }
          }
          assertResponsiveVisible(speed, in: try responsiveElement("map.speedCard", in: controller.view))
          XCTAssertNotNil(native.view?.window)
          try attachResponsiveScreenshot(host.container.view,
                                         name: "navigation-controls-\(device)-\(orientation)-\(category.rawValue)", test: self)
        }
      }
      MikshatHomeControls.updateNavigationObstruction(maneuver, frame: .zero)
    }
  }

  @MainActor
  func testNativeAndDirectInformationCardsCenterInLandscapeAndReturnToPortraitBottom() throws {
    for direct in [false, true] {
      for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
        let controller = UIViewController()
        let host = ResponsiveUIKitHost(controller, size: CGSize(width: 390, height: 844), category: category)
        defer { host.close() }
        let card: UIView
        if direct {
          let guidance = MikshatDirectGuidanceView(target: responsiveDestination, origin: responsiveLocation())
          guidance.translatesAutoresizingMaskIntoConstraints = false
          controller.view.addSubview(guidance)
          guidance.installPlacement(in: controller.view)
          card = guidance
        } else {
          let native = try XCTUnwrap(Bundle.main.loadNibNamed("NavigationControlView", owner: nil)?.first as? NavigationControlView)
          native.ownerView = controller.view
          native.isVisible = true
          card = native
        }
        defer {
          if let native = card as? NavigationControlView { native.isVisible = false }
          if let guidance = card as? MikshatDirectGuidanceView { guidance.stop() }
        }
        for (device, portrait) in responsivePortraitSizes {
          for (orientation, size) in [("portrait", portrait), ("landscape", portrait.rotated), ("portrait-return", portrait)] {
            host.resize(size)
            let prefix = direct ? "navigation.direct." : "navigation."
            let speed = try responsiveElement(prefix + "speedValue", in: card, as: UILabel.self)
            let distance = try responsiveElement(prefix + "distanceValue", in: card, as: UILabel.self)
            let time = try responsiveElement(prefix + "timeValue", in: card, as: UILabel.self)
            speed.text = "123"
            distance.text = "999.9"
            time.text = "12:59"
            host.layout()
            let safe = controller.view.safeAreaLayoutGuide.layoutFrame
            if size.width > size.height {
              XCTAssertEqual(card.frame.midX, safe.midX, accuracy: 1)
              XCTAssertEqual(card.frame.midY, safe.midY, accuracy: 1)
            } else {
              XCTAssertEqual(card.frame.maxY, safe.maxY, accuracy: 1)
              XCTAssertEqual(card.frame.minX, safe.minX, accuracy: 1)
              XCTAssertEqual(card.frame.maxX, safe.maxX, accuracy: 1)
            }
            assertResponsiveVisible(card, in: controller.view, context: "\(device) \(orientation)")
            for label in [speed, distance, time] {
              XCTAssertEqual(label.numberOfLines, 1)
              assertResponsiveLabelFits(label)
              assertResponsiveVisible(label, in: card)
            }
            XCTAssertFalse(speed.convert(speed.bounds, to: card).intersects(time.convert(time.bounds, to: card)))
            XCTAssertFalse(distance.convert(distance.bounds, to: card).intersects(time.convert(time.bounds, to: card)))
            try attachResponsiveScreenshot(host.container.view,
                                           name: "navigation-\(direct ? "direct" : "native")-\(device)-\(orientation)-\(category.rawValue)", test: self)
            let expand = NSSelectorFromString(direct ? "toggleExpanded" : "extendAction")
            XCTAssertTrue(card.responds(to: expand))
            UIView.performWithoutAnimation { _ = card.perform(expand) }
            host.layout()
            let actionIDs = direct ? ["navigation.direct.stop"] : ["navigation.stop", "navigation.sound", "navigation.settings"]
            let actions = try actionIDs.map { try responsiveElement($0, in: card) }
            for action in actions {
              assertResponsiveVisible(action, in: card, context: "expanded \(device) \(orientation)")
              assertResponsiveVisible(action, in: controller.view, context: "expanded \(device) \(orientation)")
              XCTAssertGreaterThanOrEqual(action.bounds.width, 44)
              XCTAssertGreaterThanOrEqual(action.bounds.height, 44)
            }
            for (index, action) in actions.enumerated() {
              for next in actions.dropFirst(index + 1) {
                XCTAssertFalse(action.convert(action.bounds, to: card).intersects(next.convert(next.bounds, to: card)),
                               "Expanded navigation actions overlap")
              }
            }
            try attachResponsiveScreenshot(host.container.view,
                                           name: "navigation-\(direct ? "direct" : "native")-expanded-\(device)-\(orientation)-\(category.rawValue)", test: self)
            UIView.performWithoutAnimation { _ = card.perform(expand) }
            host.layout()
          }
        }
      }
    }
  }

  @MainActor
  func testManeuversRightControlsAndCenteredNavigationCardsShareLandscapeViewport() async throws {
    defer { restoreResponsiveMapControls() }
    for direct in [false, true] {
      let controller = UIViewController()
      let host = ResponsiveUIKitHost(controller, size: CGSize(width: 568, height: 320))
      defer { host.close() }
      MikshatHomeControls.install(in: controller.view)
      let nativeButtons = try XCTUnwrap(MWMSideButtons(parentView: controller.view))
      let maneuvers = try XCTUnwrap(Bundle.main.loadNibNamed("MWMNavigationInfoView", owner: nil)?.first as? NavigationInfoView)
      maneuvers.ownerView = controller.view
      maneuvers.availableArea = controller.view.bounds
      maneuvers.state = .navigation
      let info = MWMNavigationDashboardEntity()
      info.setValue("طريق الموقع المحدد", forKey: "streetName")
      info.setValue("250", forKey: "distanceToTurn")
      info.setValue("م", forKey: "turnUnits")
      info.setValue(UIImage(systemName: "arrow.turn.up.left"), forKey: "turnImage")
      info.setValue(UIImage(systemName: "arrow.turn.up.right"), forKey: "nextTurnImage")
      maneuvers.onNavigationInfoUpdated(info)
      defer { maneuvers.state = .hidden }
      let card: UIView
      if direct {
        let guidance = MikshatDirectGuidanceView(target: responsiveDestination, origin: responsiveLocation())
        guidance.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(guidance)
        guidance.installPlacement(in: controller.view)
        card = guidance
      } else {
        let native = try XCTUnwrap(Bundle.main.loadNibNamed("NavigationControlView", owner: nil)?.first as? NavigationControlView)
        native.ownerView = controller.view
        native.isVisible = true
        card = native
      }
      defer {
        if let native = card as? NavigationControlView { native.isVisible = false }
        if let guidance = card as? MikshatDirectGuidanceView { guidance.stop() }
      }
      let expand = NSSelectorFromString(direct ? "toggleExpanded" : "extendAction")
      for (device, size) in [("compact-phone", CGSize(width: 568, height: 320)),
                             ("phone", CGSize(width: 844, height: 390)),
                             ("tablet", CGSize(width: 1024, height: 768)),
                             ("compact-phone-return", CGSize(width: 568, height: 320))] {
        host.resize(size)
        maneuvers.availableArea = controller.view.bounds
        // NavigationInfoView applies available-area changes on its production main-queue path.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          DispatchQueue.main.async { continuation.resume() }
        }
        host.layout()
        let speed = try responsiveElement("map.speedValue", in: controller.view, as: UILabel.self)
        speed.text = "123"
        let prefix = direct ? "navigation.direct." : "navigation."
        try responsiveElement(prefix + "speedValue", in: card, as: UILabel.self).text = "123"
        try responsiveElement(prefix + "distanceValue", in: card, as: UILabel.self).text = "999.9"
        try responsiveElement(prefix + "timeValue", in: card, as: UILabel.self).text = "12:59"
        var showingExpanded = false
        for expanded in [false, true, false] {
          if expanded != showingExpanded {
            UIView.performWithoutAnimation { _ = card.perform(expand) }
          }
          showingExpanded = expanded
          host.layout()
          let safe = controller.view.safeAreaLayoutGuide.layoutFrame
          XCTAssertEqual(card.frame.midX, safe.midX, accuracy: 1)
          XCTAssertEqual(card.frame.midY, safe.midY, accuracy: 1)
          assertResponsiveVisible(card, in: controller.view, context: device)
          let panels = try ["navigation.maneuverPanel", "navigation.nextManeuver", "navigation.streetPanel"]
            .map { try responsiveElement($0, in: maneuvers) }
          for panel in panels {
            XCTAssertFalse(panel.isHidden)
            XCTAssertGreaterThan(panel.bounds.width, 0)
            XCTAssertGreaterThan(panel.bounds.height, 0)
          }
          let controls = try ["map.speedCard", "map.compass", "map.qibla", "map.zoomIn", "map.zoomOut", "map.location"]
            .map { try responsiveElement($0, in: controller.view) }
          for control in controls {
            assertResponsiveVisible(control, in: controller.view, context: device)
            XCTAssertGreaterThanOrEqual(control.bounds.width, 44)
            XCTAssertGreaterThanOrEqual(control.bounds.height, 44)
            let rect = control.convert(control.bounds, to: controller.view)
            XCTAssertFalse(rect.intersects(card.frame), "\(control.accessibilityIdentifier ?? "control") overlaps \(direct ? "direct" : "native") card")
            for panel in panels {
              XCTAssertFalse(rect.intersects(panel.convert(panel.bounds, to: controller.view)),
                             "\(control.accessibilityIdentifier ?? "control") overlaps an actual maneuver panel")
            }
          }
          XCTAssertEqual(speed.numberOfLines, 1)
          assertResponsiveLabelFits(speed)
          XCTAssertNotNil(nativeButtons.view?.window)
          if expanded {
            let actionIDs = direct ? ["navigation.direct.stop"] : ["navigation.stop", "navigation.sound", "navigation.settings"]
            for identifier in actionIDs {
              let action = try responsiveElement(identifier, in: card)
              assertResponsiveVisible(action, in: controller.view, context: device)
              XCTAssertGreaterThanOrEqual(action.bounds.width, 44)
              XCTAssertGreaterThanOrEqual(action.bounds.height, 44)
            }
          }
          try attachResponsiveScreenshot(host.container.view,
                                         name: "navigation-joint-\(direct ? "direct" : "native")-\(device)-\(expanded ? "expanded" : "collapsed")", test: self)
        }
      }
    }
  }

  @MainActor
  func testDestinationRestorationAndCompassCloseReopenTheCapturedSelectedPoint() async throws {
    let map = try XCTUnwrap(MapViewController.shared())
    map.loadViewIfNeeded()
    defer { map.dismissPlacePage(); MWMRouter.stopRouting() }
    let firstTitle = "هدف محفوظ أول"
    MikshatNavigationCoordinator.restoreDestinationSelection(coordinate: responsiveSelectedPoint, title: firstTitle)
    try await waitForResponsiveSelection(responsiveSelectedPoint, title: firstTitle)
    XCTAssertFalse(MWMRouter.isRoutingActive())
    XCTAssertEqual(MWMRouter.pointsCount(), 0)

    let presenter = UIViewController()
    let host = ResponsiveUIKitHost(presenter, size: CGSize(width: 390, height: 844))
    defer { host.close() }
    let targetTitle = "هدف البوصلة المحدد"
    let compass = MikshatCompassViewController(target: responsiveDestination, name: targetTitle)
    presenter.present(compass, animated: false)
    compass.updateReadings(position: responsiveLocation(), reading: (degrees: 72, gps: false))
    try responsiveElement("mikshat.compass.close", in: compass.view, as: UIButton.self).sendActions(for: .touchUpInside)
    try await waitForResponsiveSelection(responsiveDestination, title: targetTitle)
    XCTAssertNil(presenter.presentedViewController)
    let restored = PlacePageData(localizationProvider: OpeinigHoursLocalization())
    XCTAssertFalse(restored.isMyPosition)
    XCTAssertEqual(restored.locationCoordinate.latitude, responsiveDestination.latitude, accuracy: 0.000001)
    XCTAssertEqual(restored.locationCoordinate.longitude, responsiveDestination.longitude, accuracy: 0.000001)
    XCTAssertFalse(MWMRouter.isRoutingActive())
    XCTAssertEqual(MWMRouter.pointsCount(), 0)
  }

  @MainActor
  private func waitForResponsiveSelection(_ coordinate: CLLocationCoordinate2D, title: String) async throws {
    let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      guard PlacePageData.hasData else { return false }
      let data = PlacePageData(localizationProvider: OpeinigHoursLocalization())
      return abs(data.locationCoordinate.latitude - coordinate.latitude) < 0.000001
        && abs(data.locationCoordinate.longitude - coordinate.longitude) < 0.000001
        && data.previewData.title == title
    }, object: nil)
    await fulfillment(of: [selected], timeout: 5)
    XCTAssertTrue(PlacePageData.hasData)
  }
}

@MainActor
private func restoreResponsiveMapControls() {
  guard let map = MapViewController.shared() else { return }
  map.loadViewIfNeeded()
  MikshatHomeControls.install(in: map.view)
  if let buttons = MWMSideButtons().view { MikshatHomeControls.attachMapControls(buttons) }
  MikshatHomeControls.updateNavigationObstruction(map.view, frame: .zero)
  map.view.setNeedsLayout()
  map.view.layoutIfNeeded()
}

private let responsiveSelectedPoint = CLLocationCoordinate2D(latitude: 24.65001, longitude: 46.71002)
private let responsiveDestination = CLLocationCoordinate2D(latitude: 25.1, longitude: 47.2)
private let responsiveCoordinateText = [
  "dd": "24.650010\n46.710020",
  "ddm": "N 24° 39.001′\nE 046° 42.601′",
  "dms": "N 24° 39′ 00.04″\nE 046° 42′ 36.07″",
]
private let responsivePortraitSizes: [(String, CGSize)] = [
  ("compact-phone", CGSize(width: 320, height: 568)),
  ("phone", CGSize(width: 390, height: 844)),
  ("large-phone", CGSize(width: 430, height: 932)),
  ("tablet", CGSize(width: 768, height: 1024)),
]

private extension CGSize {
  var rotated: CGSize { CGSize(width: height, height: width) }
}

private func responsiveLocation() -> CLLocation {
  CLLocation(coordinate: responsiveSelectedPoint, altitude: 80, horizontalAccuracy: 5, verticalAccuracy: 5,
             course: 72, speed: 123 / 3.6, timestamp: Date())
}

@MainActor
private func responsiveDescendants(_ root: UIView) -> [UIView] {
  [root] + root.subviews.flatMap { responsiveDescendants($0) }
}

@MainActor
private func responsiveElement(_ identifier: String, in root: UIView,
                               file: StaticString = #filePath, line: UInt = #line) throws -> UIView {
  try responsiveElement(identifier, in: root, as: UIView.self, file: file, line: line)
}

@MainActor
private func responsiveElement<T: UIView>(_ identifier: String, in root: UIView, as type: T.Type,
                                         file: StaticString = #filePath, line: UInt = #line) throws -> T {
  try XCTUnwrap(responsiveDescendants(root).first { $0.accessibilityIdentifier == identifier } as? T,
                "Missing \(identifier)", file: file, line: line)
}

@MainActor
private func assertResponsiveVisible(_ view: UIView, in viewport: UIView, context: String = "",
                                     file: StaticString = #filePath, line: UInt = #line) {
  let rect = view.convert(view.bounds, to: viewport)
  XCTAssertFalse(view.isHidden, "\(view.accessibilityIdentifier ?? "view") \(context)", file: file, line: line)
  XCTAssertGreaterThan(rect.width, 0, context, file: file, line: line)
  XCTAssertGreaterThan(rect.height, 0, context, file: file, line: line)
  XCTAssertTrue(viewport.bounds.insetBy(dx: -1, dy: -1).contains(rect),
                "\(view.accessibilityIdentifier ?? "view") \(rect) outside \(viewport.bounds) \(context)", file: file, line: line)
}

@MainActor
private func assertResponsiveLabelFits(_ label: UILabel, file: StaticString = #filePath, line: UInt = #line) {
  let text = label.text ?? ""
  XCTAssertFalse(text.isEmpty, file: file, line: line)
  let lines = text.components(separatedBy: "\n")
  let minimumFont = label.font.withSize(label.font.pointSize * (label.adjustsFontSizeToFitWidth ? label.minimumScaleFactor : 1))
  let widths = lines.map { ($0 as NSString).size(withAttributes: [.font: minimumFont]).width }
  XCTAssertLessThanOrEqual(widths.max() ?? 0, label.bounds.width + 1,
                           "Full coordinate text must fit even at its minimum permitted font", file: file, line: line)
  XCTAssertGreaterThanOrEqual(label.bounds.height + 1, minimumFont.lineHeight * CGFloat(lines.count), file: file, line: line)
}

@MainActor
private func assertSelectedCoordinateRow(_ format: String, in coordinates: UIView,
                                         file: StaticString = #filePath, line: UInt = #line) throws {
  let prefix = "placePage.coordinates." + format
  let row = try responsiveElement(prefix, in: coordinates, file: file, line: line)
  let latitude = try responsiveElement(prefix + ".latitude", in: coordinates, as: UILabel.self, file: file, line: line)
  let longitude = try responsiveElement(prefix + ".longitude", in: coordinates, as: UILabel.self, file: file, line: line)
  XCTAssertEqual((latitude.text ?? "") + "\n" + (longitude.text ?? ""), responsiveCoordinateText[format], file: file, line: line)
  XCTAssertEqual(latitude.numberOfLines, 1, file: file, line: line)
  XCTAssertEqual(longitude.numberOfLines, 1, file: file, line: line)
  assertResponsiveLabelFits(latitude, file: file, line: line)
  assertResponsiveLabelFits(longitude, file: file, line: line)
  let copy = try responsiveElement(prefix + ".copy", in: coordinates, as: UIButton.self, file: file, line: line)
  XCTAssertGreaterThanOrEqual(copy.bounds.width, 44, file: file, line: line)
  XCTAssertGreaterThanOrEqual(copy.bounds.height, 44, file: file, line: line)
  XCTAssertFalse((copy.accessibilityLabel ?? "").isEmpty, file: file, line: line)
  assertResponsiveVisible(latitude, in: row, file: file, line: line)
  assertResponsiveVisible(longitude, in: row, file: file, line: line)
  XCTAssertFalse(copy.convert(copy.bounds, to: row).intersects(latitude.convert(latitude.bounds, to: row)), file: file, line: line)
}

/// Hosts production UIKit views in an on-screen, non-key window. Rotation resizes the same hierarchy.
@MainActor
private final class ResponsiveUIKitHost {
  let window: UIWindow
  let container = UIViewController()
  let controller: UIViewController
  private let fitContentHeight: Bool
  private let category: UIContentSizeCategory

  init(_ controller: UIViewController, size: CGSize, category: UIContentSizeCategory = .large,
       fitContentHeight: Bool = false) {
    self.controller = controller
    self.fitContentHeight = fitContentHeight
    self.category = category
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
    container.view.backgroundColor = .systemBackground
    container.view.frame = window.bounds
    container.view.semanticContentAttribute = .forceRightToLeft
    container.addChild(controller)
    container.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
      UITraitCollection(preferredContentSizeCategory: category), UITraitCollection(layoutDirection: .rightToLeft),
      UITraitCollection(userInterfaceStyle: .light),
    ]), forChild: controller)
    controller.loadViewIfNeeded()
    controller.view.semanticContentAttribute = .forceRightToLeft
    controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.view.addSubview(controller.view)
    controller.didMove(toParent: container)
    window.rootViewController = container
    window.isHidden = false
    resize(size)
  }

  func resize(_ size: CGSize) {
    window.frame = CGRect(origin: .zero, size: size)
    container.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
      UITraitCollection(preferredContentSizeCategory: category), UITraitCollection(layoutDirection: .rightToLeft),
      UITraitCollection(userInterfaceStyle: .light),
      UITraitCollection(userInterfaceIdiom: min(size.width, size.height) >= 600 ? .pad : .phone),
      UITraitCollection(horizontalSizeClass: size.width >= 600 ? .regular : .compact),
      UITraitCollection(verticalSizeClass: size.height < 500 ? .compact : .regular),
    ]), forChild: controller)
    container.view.frame = window.bounds
    controller.view.frame = container.view.bounds
    layout()
  }

  func layout() {
    for _ in 0..<4 {
      if fitContentHeight {
        let fitting = controller.view.systemLayoutSizeFitting(CGSize(width: container.view.bounds.width, height: 0),
                                                              withHorizontalFittingPriority: .required,
                                                              verticalFittingPriority: .fittingSizeLevel)
        controller.view.frame = CGRect(origin: .zero, size: fitting)
      }
      container.view.setNeedsLayout()
      controller.view.setNeedsLayout()
      container.view.layoutIfNeeded()
      controller.view.layoutIfNeeded()
    }
  }

  func close() {
    window.isHidden = true
    window.rootViewController = nil
  }
}

@MainActor
private final class ResponsiveContentController: UIViewController {
  let content: UIView
  init(content: UIView) { self.content = content; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func viewDidLoad() {
    super.viewDidLoad()
    let scroll = UIScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)
    scroll.addSubview(content)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
    ])
  }
}

private final class ResponsivePlaceInfoData: PlacePageInfoData {
  override var latitude: Double { responsiveSelectedPoint.latitude }
  override var longitude: Double { responsiveSelectedPoint.longitude }
  override var phones: [PlacePagePhone] { [] }
}

private final class ResponsivePlacePreviewData: PlacePagePreviewData {
  override var title: String? { "النقطة المحددة" }
  override var subtitle: String? { nil }
  override var secondarySubtitle: String? { nil }
  override var coordinates: String? { "old coordinates must not duplicate the compact selected point" }
  override var isMyPosition: Bool { false }
}

private final class ResponsivePlacePreviewDelegate: PlacePageHeaderViewControllerDelegate {
  var copies: [String] = []
  var contentSizeChanges = 0
  func previewDidCopy(_ content: String) { copies.append(content) }
  func previewDidChangeContentSize() { contentSizeChanges += 1 }
  func previewDidPressClose() {}
  func previewDidPressExpand() {}
  func previewDidSelectTrackCandidate(_ track: PlacePageTrackSelectionData) {}
  func previewDidPressShare(from sourceView: UIView) {}
  func previewDidPressExportTrack(_ type: FileType, from sourceView: UIView) {}
  func previewDidFinishEditingTitle(_ newTitle: String) {}
}

@MainActor
private func attachResponsiveScreenshot(_ view: UIView, name: String, test: XCTestCase) throws {
  view.layoutIfNeeded()
  let format = UIGraphicsImageRendererFormat()
  format.scale = 2
  let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { view.layer.render(in: $0.cgContext) }
  let directory = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent("responsive-\(name)-fixture.png"), options: .atomic)
  let attachment = XCTAttachment(image: image)
  attachment.name = "responsive-\(name)-fixture"
  attachment.lifetime = .keepAlways
  test.add(attachment)
}
