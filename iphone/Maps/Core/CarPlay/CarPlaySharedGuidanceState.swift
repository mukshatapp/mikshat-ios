import CoreLocation

struct CarPlayGuidanceIdentity: Equatable {
  enum Kind: Equatable {
    case vehicle
    case direct
  }

  let kind: Kind
  let latitude: Double
  let longitude: Double

  init?(kind: Kind, coordinate: CLLocationCoordinate2D) {
    guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
    self.kind = kind
    latitude = coordinate.latitude
    longitude = coordinate.longitude
  }
}

struct CarPlaySharedGuidanceState {
  enum Change: Equatable {
    case unchanged
    case started
    case changed
    case ended
  }

  private(set) var current: CarPlayGuidanceIdentity?

  mutating func update(_ identity: CarPlayGuidanceIdentity?) -> Change {
    guard identity != current else { return .unchanged }
    let previous = current
    current = identity
    if previous == nil {
      return .started
    }
    return identity == nil ? .ended : .changed
  }

  mutating func reset() {
    current = nil
  }
}
