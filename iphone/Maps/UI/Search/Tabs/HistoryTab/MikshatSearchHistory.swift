import Foundation
import CoreLocation

struct MikshatSearchLocation: Codable, Equatable {
  let id: String
  let title: String
  let subtitle: String
  let query: String
  let latitude: Double
  let longitude: Double

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  var isValid: Bool {
    latitude.isFinite && longitude.isFinite && CLLocationCoordinate2DIsValid(coordinate) &&
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func isSamePoint(as coordinate: CLLocationCoordinate2D) -> Bool {
    abs(latitude - coordinate.latitude) < 0.000001 && abs(longitude - coordinate.longitude) < 0.000001
  }
}

enum MikshatSearchHistoryEntry {
  case location(MikshatSearchLocation)
  case unresolvedQuery(String)
}

final class MikshatSearchHistoryStore {
  static let storageKey = "mikshat_search_location_history_v2"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var locations: [MikshatSearchLocation] {
    guard let data = defaults.data(forKey: Self.storageKey),
          let saved = try? JSONDecoder().decode([MikshatSearchLocation].self, from: data) else { return [] }
    return Array(saved.filter(\.isValid).prefix(50))
  }

  func remember(_ location: MikshatSearchLocation) {
    guard location.isValid else { return }
    let existing = locations
    let samePoint = existing.first { $0.isSamePoint(as: location.coordinate) }
    let saved = MikshatSearchLocation(id: samePoint?.id ?? location.id, title: location.title,
                                      subtitle: location.subtitle, query: location.query,
                                      latitude: location.latitude, longitude: location.longitude)
    let updated = [saved] + existing.filter { !$0.isSamePoint(as: location.coordinate) }
    if let data = try? JSONEncoder().encode(Array(updated.prefix(50))) {
      defaults.set(data, forKey: Self.storageKey)
    }
  }

  func clear() {
    defaults.removeObject(forKey: Self.storageKey)
  }
}

enum MikshatSearchLocations {
  private static let legacyKey = "mikshat_search_locations"
  private static let store = MikshatSearchHistoryStore()

  // Preserve coordinates recorded by older builds and by coordinate entry.
  static func remember(_ coordinate: CLLocationCoordinate2D, query: String) {
    guard Settings.searchHistoryEnabled(), CLLocationCoordinate2DIsValid(coordinate) else { return }
    let queries = MWMSearchFrameworkHelper.lastSearchQueries()
    var values = UserDefaults.standard.dictionary(forKey: legacyKey) as? [String: [Double]] ?? [:]
    values = values.filter { queries.contains($0.key) }
    let historyQuery = queries.first { normalized($0) == normalized(query) } ?? query
    values[historyQuery] = [coordinate.latitude, coordinate.longitude]
    UserDefaults.standard.set(values, forKey: legacyKey)
  }

  static func rememberLocation(_ coordinate: CLLocationCoordinate2D, title: String,
                               subtitle: String, query: String) {
    guard Settings.searchHistoryEnabled() else { return }
    let name = normalized(title).isEmpty ? normalized(query) : title
    store.remember(MikshatSearchLocation(id: UUID().uuidString, title: name, subtitle: subtitle,
                                         query: query, latitude: coordinate.latitude, longitude: coordinate.longitude))
    remember(coordinate, query: query)
  }

  static func markVisited(_ location: MikshatSearchLocation) {
    guard Settings.searchHistoryEnabled() else { return }
    store.remember(location)
  }

  static func entries(queries: [String]) -> [MikshatSearchHistoryEntry] {
    guard Settings.searchHistoryEnabled() else { return [] }
    let saved = store.locations
    let represented = Set(saved.map { normalized($0.query) })
    var entries = saved.map { MikshatSearchHistoryEntry.location($0) }
    for query in queries where !represented.contains(normalized(query)) {
      if let coordinate = legacyCoordinate(for: query) {
        guard !saved.contains(where: { $0.isSamePoint(as: coordinate) }) else { continue }
        let location = MikshatSearchLocation(id: "legacy:" + query, title: query, subtitle: "", query: query,
                                             latitude: coordinate.latitude, longitude: coordinate.longitude)
        entries.append(.location(location))
      } else {
        entries.append(.unresolvedQuery(query))
      }
    }
    return entries
  }

  static func coordinate(for query: String) -> CLLocationCoordinate2D? {
    guard Settings.searchHistoryEnabled() else { return nil }
    let matches = store.locations.filter { normalized($0.query) == normalized(query) }
    if matches.count == 1 { return matches[0].coordinate }
    if matches.count > 1 { return nil }
    return legacyCoordinate(for: query)
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: legacyKey)
    store.clear()
  }

  private static func normalized(_ query: String) -> String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func legacyCoordinate(for query: String) -> CLLocationCoordinate2D? {
    let values = UserDefaults.standard.dictionary(forKey: legacyKey) as? [String: [Double]] ?? [:]
    let pair = values[query] ?? values.first { normalized($0.key) == normalized(query) }?.value
    if let pair, pair.count == 2 {
      let coordinate = CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
      if pair[0].isFinite, pair[1].isFinite, CLLocationCoordinate2DIsValid(coordinate) { return coordinate }
    }
    guard let parsed = MikshatNavigationMath.parseDecimalPair(query) else { return nil }
    return CLLocationCoordinate2D(latitude: parsed.latitude, longitude: parsed.longitude)
  }
}
