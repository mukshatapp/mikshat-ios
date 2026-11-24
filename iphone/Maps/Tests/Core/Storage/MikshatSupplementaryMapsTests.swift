@testable import Organic_Maps__Debug_
import XCTest

final class MikshatSupplementaryMapsTests: XCTestCase {
  private func isolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "MikshatSupplementaryMapsTests.\(UUID().uuidString)")!
  }

  @MainActor
  func testEveryBundledMapCanActivateDeactivateAndReactivateWithoutDeletingItsFile() throws {
    for map in MikshatSupplementaryMaps.catalog {
      let url = try XCTUnwrap(Bundle.main.url(forResource: map.id, withExtension: "mwm",
                                             subdirectory: "SupplementaryMaps"), map.id)
      let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)
      XCTAssertGreaterThan(size.uint64Value, 0, map.id)
      defer { _ = FrameworkHelper.setSupplementaryMap(map.id, enabled: false) }

      for _ in 0..<2 {
        XCTAssertTrue(FrameworkHelper.setSupplementaryMap(map.id, enabled: true), map.id)
        XCTAssertTrue(FrameworkHelper.setSupplementaryMap(map.id, enabled: false), map.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), map.id)
      }
    }
  }

  @MainActor
  func testSelectionRestoresOnlyKnownMapsAndOnlyOnce() {
    let defaults = isolatedDefaults()
    defaults.set(["desert-kuwait", "desert-qatar", "World", "unknown"],
                 forKey: MikshatSupplementaryMaps.selectionKey)
    var calls: [(String, Bool)] = []
    let maps = MikshatSupplementaryMaps(defaults: defaults) { id, enabled in
      calls.append((id, enabled))
      return true
    }
    maps.restoreSelection()
    maps.restoreSelection()
    XCTAssertEqual(calls.map { $0.0 }, ["desert-kuwait", "desert-qatar"])
    XCTAssertTrue(calls.allSatisfy { $0.1 })
    XCTAssertEqual(maps.enabledIDs, ["desert-kuwait", "desert-qatar"])
  }

  @MainActor
  func testSuccessfulTogglePersistsAndDisabledMapStaysOffAfterRelaunch() {
    let defaults = isolatedDefaults()
    let maps = MikshatSupplementaryMaps(defaults: defaults) { _, _ in true }
    maps.restoreSelection()
    XCTAssertTrue(maps.enabledIDs.isEmpty)
    XCTAssertTrue(maps.setEnabled(true, id: "desert-ksa-north"))
    XCTAssertTrue(maps.setEnabled(true, id: "desert-qatar"))
    XCTAssertTrue(maps.setEnabled(false, id: "desert-ksa-north"))
    var restored: [String] = []
    let relaunched = MikshatSupplementaryMaps(defaults: defaults) { id, _ in
      restored.append(id)
      return true
    }
    relaunched.restoreSelection()
    XCTAssertEqual(restored, ["desert-qatar"])
    XCTAssertEqual(relaunched.enabledIDs, ["desert-qatar"])
  }

  @MainActor
  func testFailedActivationAndDeactivationDoNotChangeSelection() {
    let defaults = isolatedDefaults()
    var succeeds = false
    let maps = MikshatSupplementaryMaps(defaults: defaults) { _, _ in succeeds }
    maps.restoreSelection()
    XCTAssertFalse(maps.setEnabled(true, id: "desert-kuwait"))
    XCTAssertTrue(maps.enabledIDs.isEmpty)
    XCTAssertNil(defaults.stringArray(forKey: MikshatSupplementaryMaps.selectionKey))
    succeeds = true
    XCTAssertTrue(maps.setEnabled(true, id: "desert-kuwait"))
    succeeds = false
    XCTAssertFalse(maps.setEnabled(false, id: "desert-kuwait"))
    XCTAssertEqual(maps.enabledIDs, ["desert-kuwait"])
    XCTAssertEqual(defaults.stringArray(forKey: MikshatSupplementaryMaps.selectionKey), ["desert-kuwait"])
    XCTAssertFalse(maps.setEnabled(true, id: "World"))
  }
}
