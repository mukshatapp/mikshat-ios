@testable import Organic_Maps__Debug_
import XCTest
import UIKit

final class MikshatSupplementaryMapsTests: XCTestCase {
  private var defaultsSuites: [String] = []

  private func isolatedDefaults() -> UserDefaults {
    let name = "MikshatSupplementaryMapsTests.\(UUID().uuidString)"
    defaultsSuites.append(name)
    return UserDefaults(suiteName: name)!
  }

  override func tearDown() {
    for name in defaultsSuites { UserDefaults.standard.removePersistentDomain(forName: name) }
    defaultsSuites.removeAll()
    super.tearDown()
  }

  @MainActor
  func testEveryBundledMapCanActivateDeactivateAndReactivateWithoutDeletingItsFile() throws {
    let controller = try XCTUnwrap(MapViewController.shared())
    controller.loadViewIfNeeded()
    let button = try XCTUnwrap(descendants(in: controller.view).compactMap { $0 as? UIButton }
      .first { $0.accessibilityIdentifier == "map.layers" })
    XCTAssertNil(button.menu, "The satellite button must not expose optional map choices")
    XCTAssertFalse(button.showsMenuAsPrimaryAction)
    XCTAssertTrue(MikshatSupplementaryMaps.shared.enableAll())
    XCTAssertEqual(MikshatSupplementaryMaps.shared.enabledIDs, Set(MikshatSupplementaryMaps.catalog.map(\.id)))

    for map in MikshatSupplementaryMaps.catalog {
      let url = try XCTUnwrap(Bundle.main.url(forResource: map.id, withExtension: "mwm",
                                             subdirectory: "SupplementaryMaps"), map.id)
      let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)
      XCTAssertGreaterThan(size.uint64Value, 0, map.id)
      // Leave the production singleton's automatically enabled maps registered.
      defer { _ = FrameworkHelper.setSupplementaryMap(map.id, enabled: true) }

      for _ in 0..<2 {
        XCTAssertTrue(FrameworkHelper.setSupplementaryMap(map.id, enabled: true), map.id)
        XCTAssertTrue(FrameworkHelper.setSupplementaryMap(map.id, enabled: false), map.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), map.id)
      }
    }
  }

  @MainActor
  func testAllBundledMapsActivateOnceIgnoringLegacySelections() {
    let defaults = isolatedDefaults()
    defaults.set(["desert-kuwait", "desert-qatar", "World", "unknown"],
                 forKey: MikshatSupplementaryMaps.legacySelectionKey)
    var calls: [String] = []
    let maps = MikshatSupplementaryMaps(defaults: defaults) { id in
      calls.append(id)
      return true
    }
    XCTAssertTrue(maps.enableAll())
    XCTAssertTrue(maps.enableAll())
    XCTAssertEqual(calls, MikshatSupplementaryMaps.catalog.map(\.id))
    XCTAssertEqual(maps.enabledIDs, Set(MikshatSupplementaryMaps.catalog.map(\.id)))
    XCTAssertNil(defaults.object(forKey: MikshatSupplementaryMaps.legacySelectionKey))
  }

  @MainActor
  func testFreshInstallAndExistingDisabledMapsActivateAfterRelaunch() {
    let oldSelections: [Any?] = [nil, false, [String](), ["desert-qatar"]]
    for oldSelection in oldSelections {
      let defaults = isolatedDefaults()
      defaults.set(oldSelection, forKey: MikshatSupplementaryMaps.legacySelectionKey)
      var calls: [String] = []
      let maps = MikshatSupplementaryMaps(defaults: defaults) { id in
        calls.append(id)
        return true
      }
      XCTAssertTrue(maps.enableAll())
      XCTAssertEqual(calls, MikshatSupplementaryMaps.catalog.map(\.id))
      XCTAssertNil(defaults.object(forKey: MikshatSupplementaryMaps.legacySelectionKey))

      var restored: [String] = []
      let relaunched = MikshatSupplementaryMaps(defaults: defaults) { id in
        restored.append(id)
        return true
      }
      XCTAssertTrue(relaunched.enableAll())
      XCTAssertEqual(restored, MikshatSupplementaryMaps.catalog.map(\.id))
      XCTAssertEqual(relaunched.enabledIDs, Set(MikshatSupplementaryMaps.catalog.map(\.id)))
    }
  }

  @MainActor
  func testFailedActivationRetriesOnlyMissingMaps() {
    let defaults = isolatedDefaults()
    var failingIDs: Set<String> = ["desert-ksa-south"]
    var calls: [String] = []
    let maps = MikshatSupplementaryMaps(defaults: defaults) { id in
      calls.append(id)
      return !failingIDs.contains(id)
    }
    XCTAssertFalse(maps.enableAll())
    XCTAssertEqual(calls, MikshatSupplementaryMaps.catalog.map(\.id))
    XCTAssertEqual(maps.enabledIDs, Set(MikshatSupplementaryMaps.catalog.map(\.id)).subtracting(failingIDs))
    calls.removeAll()
    XCTAssertFalse(maps.enableAll())
    XCTAssertEqual(calls, ["desert-ksa-south"])
    failingIDs.removeAll()
    calls.removeAll()
    XCTAssertTrue(maps.enableAll())
    XCTAssertEqual(calls, ["desert-ksa-south"])
    calls.removeAll()
    XCTAssertTrue(maps.enableAll())
    XCTAssertTrue(calls.isEmpty, "Foreground retries must not re-register successful maps")
    XCTAssertNil(defaults.object(forKey: MikshatSupplementaryMaps.legacySelectionKey))
  }

  @MainActor
  private func descendants(in view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants(in: $0) }
  }
}
