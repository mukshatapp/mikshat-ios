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
  static let selectionKey = "mikshat_supplementary_maps_enabled"
  static let shared = MikshatSupplementaryMaps(defaults: .standard) { id, enabled in
    FrameworkHelper.setSupplementaryMap(id, enabled: enabled)
  }

  private let defaults: UserDefaults
  private let apply: (String, Bool) -> Bool
  private var didRestore = false
  private(set) var enabledIDs: Set<String> = []

  init(defaults: UserDefaults, apply: @escaping (String, Bool) -> Bool) {
    self.defaults = defaults
    self.apply = apply
  }

  func restoreSelection() {
    assert(Thread.isMainThread)
    guard !didRestore else { return }
    didRestore = true
    let saved = Set(defaults.stringArray(forKey: Self.selectionKey) ?? [])
    for map in Self.catalog where saved.contains(map.id) {
      if apply(map.id, true) { enabledIDs.insert(map.id) }
    }
  }

  @discardableResult
  func setEnabled(_ enabled: Bool, id: String) -> Bool {
    assert(Thread.isMainThread)
    guard Self.catalog.contains(where: { $0.id == id }) else { return false }
    guard enabledIDs.contains(id) != enabled else { return true }
    guard apply(id, enabled) else { return false }
    if enabled { enabledIDs.insert(id) } else { enabledIDs.remove(id) }
    defaults.set(Self.catalog.map(\.id).filter { enabledIDs.contains($0) }, forKey: Self.selectionKey)
    return true
  }
}
