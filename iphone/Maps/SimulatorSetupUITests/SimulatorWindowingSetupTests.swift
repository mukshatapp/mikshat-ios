import XCTest
import UIKit

/// Changes only the freshly created CI iPad's user setting. The application
/// keeps its normal multitasking support and Info.plist in every build.
final class SimulatorWindowingSetupTests: XCTestCase {
  @MainActor
  func testSelectFullScreenAppsOnTheIsolatedIPad() throws {
    continueAfterFailure = false
    XCTAssertEqual(UIDevice.current.userInterfaceIdiom, .pad,
                   "Run this setup target only on the isolated iPad simulator")
    XCUIDevice.shared.orientation = .portrait
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    settings.launch()
    defer { settings.terminate() }
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15))

    let multitasking = settings.descendants(matching: .any)
      .matching(NSPredicate(format: "label IN %@", ["Multitasking & Gestures", "Multitasking and Gestures"] as NSArray))
      .firstMatch
    // Use ordinary user scrolling in Settings' sidebar if the row is below
    // its visible portion. No SpringBoard preference keys or private APIs.
    for _ in 0..<8 {
      if multitasking.exists && multitasking.isHittable { break }
      let start = settings.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.82))
      let end = settings.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.28))
      start.press(forDuration: 0.05, thenDragTo: end)
    }
    guard multitasking.waitForExistence(timeout: 5), multitasking.isHittable else {
      recordSettings(settings, name: "missing-multitasking-settings")
      XCTFail("The iPad simulator must expose Settings → Multitasking & Gestures.\n" + settings.debugDescription)
      return
    }
    multitasking.tap()
    let fullScreen = settings.descendants(matching: .any)
      .matching(NSPredicate(format: "label IN %@", ["Full Screen Apps", "Full-Screen Apps"] as NSArray))
      .firstMatch
    guard fullScreen.waitForExistence(timeout: 10), fullScreen.isHittable else {
      recordSettings(settings, name: "missing-full-screen-apps-option")
      XCTFail("The iPad simulator must expose the Full Screen Apps windowing mode.\n" + settings.debugDescription)
      return
    }
    fullScreen.tap()
    recordSettings(settings, name: "full-screen-apps-selected")
    print("MIKSHAT_SIMULATOR_FULLSCREEN_SETUP selectedFullScreenApps=true selectedTrait=\(fullScreen.isSelected) value=\(String(describing: fullScreen.value))")
    // The following 47 hosted cases independently require the actual app scene
    // to accept orientation changes and reach matching window/map dimensions.
    // A successful Settings tap alone is never treated as layout coverage.
  }

  @MainActor
  private func recordSettings(_ settings: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: settings.screenshot())
    attachment.name = "simulator-setup-" + name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
