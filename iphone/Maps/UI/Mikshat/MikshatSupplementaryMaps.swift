import Foundation

struct MikshatSupplementaryMap: Equatable {
  let id: String
  let titleKey: String
}

final class MikshatSupplementaryMaps {
  static let catalog: [MikshatSupplementaryMap] = [
    .init(id: "desert-ksa-north", titleKey: "mikshat_map_ksa_north"),
    .init(id: "desert-ksa-south", titleKey: "mikshat_map_ksa_south"),
    .init(id: "desert-kuwait", titleKey: "mikshat_map_kuwait"),
    .init(id: "desert-qatar", titleKey: "mikshat_map_qatar"),
  ]
  static let legacySelectionKey = "mikshat_supplementary_maps_enabled"
  static let shared = MikshatSupplementaryMaps(defaults: .standard) { id in
    FrameworkHelper.setSupplementaryMap(id, enabled: true)
  }

  private let activate: (String) -> Bool
  private(set) var enabledIDs: Set<String> = []

  init(defaults: UserDefaults, activate: @escaping (String) -> Bool) {
    self.activate = activate
    // Every bundled map is now part of the base map, including for existing
    // users who had previously disabled some or all of the optional layers.
    defaults.removeObject(forKey: Self.legacySelectionKey)
  }

  @discardableResult
  func enableAll() -> Bool {
    assert(Thread.isMainThread)
    for map in Self.catalog where !enabledIDs.contains(map.id) {
      if activate(map.id) { enabledIDs.insert(map.id) }
    }
    return enabledIDs.count == Self.catalog.count
  }
}
