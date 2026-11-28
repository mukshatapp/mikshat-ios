import CarPlay
@testable import Organic_Maps__Debug_
import XCTest

final class MapTemplateBuilderTests: XCTestCase {
  func testGPSRemainsAvailableAcrossPositionModes() {
    let modes: [MWMMyPositionMode] = [.follow, .followAndRotate, .notFollow, .pendingPosition, .notFollowNoPosition]
    for mode in modes {
      let template = CPMapTemplate()
      MapTemplateBuilder.setupMapButtons(template, positionMode: mode, northUp: true)

      XCTAssertEqual(template.mapButtons.count, 3, "position mode \(mode.rawValue)")
      XCTAssertEqual(template.mapButtons.first?.accessibilityLabel, L("mikshat_carplay_gps"))
      XCTAssertFalse(template.hidesButtonsWithNavigationBar)
      for button in template.mapButtons {
        XCTAssertNotNil(button.image)
        XCTAssertNotNil(button.focusedImage)
      }
    }
  }

  func testOrientationButtonReflectsNorthAndHeadingModes() throws {
    let template = CPMapTemplate()
    MapTemplateBuilder.setupMapButtons(template, positionMode: .follow, northUp: true)
    let northButton = try XCTUnwrap(template.mapButtons.dropFirst().first)
    XCTAssertEqual(northButton.accessibilityLabel, L("mikshat_carplay_north_up"))

    MapTemplateBuilder.setupMapButtons(template, positionMode: .followAndRotate, northUp: false)
    let headingButton = try XCTUnwrap(template.mapButtons.dropFirst().first)
    XCTAssertEqual(headingButton.accessibilityLabel, L("mikshat_carplay_heading_up"))
    XCTAssertNotEqual(northButton.image?.pngData(), headingButton.image?.pngData())
    XCTAssertEqual(template.mapButtons.count, 3)
  }

  func testPanningRetainsGPSAndBothZoomControls() {
    let template = CPMapTemplate()
    MapTemplateBuilder.configurePanUI(template)

    XCTAssertEqual(template.mapButtons.map(\.accessibilityLabel),
                   [L("mikshat_carplay_gps"), L("zoom_in"), L("zoom_out")])
    XCTAssertFalse(template.hidesButtonsWithNavigationBar)
    XCTAssertTrue(template.leadingNavigationBarButtons.isEmpty)
    XCTAssertEqual(template.trailingNavigationBarButtons.map(\.title), [L("done")])
  }

  func testNavigationIncludesSaveInformationAndStopWithinButtonLimits() {
    let template = MapTemplateBuilder.buildNavigationTemplate(positionMode: .followAndRotate)

    XCTAssertEqual(template.leadingNavigationBarButtons.count, 2)
    XCTAssertEqual(template.leadingNavigationBarButtons.last?.title, L("mikshat_carplay_save_location"))
    XCTAssertEqual(template.trailingNavigationBarButtons.map(\.title),
                   [L("mikshat_carplay_trip_info"), L("navigation_stop_button").capitalized])
    XCTAssertEqual(template.mapButtons.count, 3)
    XCTAssertFalse(template.hidesButtonsWithNavigationBar)
  }

  func testLeavingPanningRestoresDestinationAndSaving() {
    let template = CPMapTemplate()
    MapTemplateBuilder.configurePanUI(template)
    MapTemplateBuilder.configureBaseUI(template, positionMode: .follow, isOnRoute: false)

    XCTAssertEqual(template.leadingNavigationBarButtons.map(\.title),
                   [L("pick_destination"), L("mikshat_carplay_save_location")])
    XCTAssertEqual(template.trailingNavigationBarButtons.count, 2)
    XCTAssertEqual(template.trailingNavigationBarButtons.last?.title, L("mikshat_carplay_trip_info"))
    XCTAssertEqual(template.mapButtons.count, 3)
    XCTAssertEqual(template.mapButtons.first?.accessibilityLabel, L("mikshat_carplay_gps"))
  }

  func testLeavingPanningRestoresActiveTripActions() {
    let template = CPMapTemplate()
    MapTemplateBuilder.configurePanUI(template)
    MapTemplateBuilder.configureNavigationUI(template, positionMode: .notFollow)

    XCTAssertEqual(template.leadingNavigationBarButtons.count, 2)
    XCTAssertEqual(template.leadingNavigationBarButtons.last?.title, L("mikshat_carplay_save_location"))
    XCTAssertEqual(template.trailingNavigationBarButtons.map(\.title),
                   [L("mikshat_carplay_trip_info"), L("navigation_stop_button").capitalized])
    XCTAssertEqual(template.mapButtons.first?.accessibilityLabel, L("mikshat_carplay_gps"))
    XCTAssertFalse(template.hidesButtonsWithNavigationBar)
  }

  func testReconfiguredTemplateIsNotRetainedByItsButtonHandlers() {
    weak var releasedTemplate: CPMapTemplate?
    autoreleasepool {
      let template = MapTemplateBuilder.buildBaseTemplate(positionMode: .follow, isOnRoute: false)
      MapTemplateBuilder.configurePanUI(template)
      MapTemplateBuilder.configureNavigationUI(template, positionMode: .followAndRotate)
      releasedTemplate = template
    }

    XCTAssertNil(releasedTemplate)
  }
}
