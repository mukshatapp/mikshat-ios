import CoreLocation
import Foundation

struct CarPlayTripMetrics {
  struct Snapshot {
    let speedMetersPerSecond: Double?
    let distanceMeters: Double?
    let remainingTime: TimeInterval?
    let arrivalDate: Date?

    static let empty = Snapshot(speedMetersPerSecond: nil,
                                distanceMeters: nil,
                                remainingTime: nil,
                                arrivalDate: nil)
  }

  private struct Destination: Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
      latitude = coordinate.latitude
      longitude = coordinate.longitude
    }
  }

  private struct SpeedSample {
    let timestamp: Date
    let metersPerSecond: Double
  }

  private enum Constants {
    static let maximumLocationAge: TimeInterval = 10
    static let maximumFutureLocationOffset: TimeInterval = 1
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 100
    static let minimumMovingSpeed: CLLocationSpeed = 1
    static let speedWindow: TimeInterval = 20
    static let minimumSpeedSampleCount = 3
    static let minimumSpeedSampleSpan: TimeInterval = 2
    static let maximumDirectETA: TimeInterval = 48 * 60 * 60
  }

  private var destination: Destination?
  private var isDirect = false
  private var speedSamples = [SpeedSample]()
  private var lastLocationTimestamp: Date?

  mutating func reset() {
    destination = nil
    isDirect = false
    speedSamples.removeAll(keepingCapacity: true)
    lastLocationTimestamp = nil
  }

  mutating func update(location: CLLocation?,
                       directDestination: CLLocationCoordinate2D?,
                       routeDistance: Double?,
                       routeDuration: TimeInterval?,
                       now: Date = Date()) -> Snapshot {
    let newDestination = directDestination.map(Destination.init)
    let newIsDirect = directDestination != nil
    if newIsDirect != isDirect || newDestination != destination {
      speedSamples.removeAll(keepingCapacity: true)
      destination = newDestination
      isDirect = newIsDirect
    }

    guard let location, Self.isUsable(location, now: now) else {
      speedSamples.removeAll(keepingCapacity: true)
      lastLocationTimestamp = nil
      return .empty
    }
    if let lastLocationTimestamp, location.timestamp < lastLocationTimestamp {
      return .empty
    }
    lastLocationTimestamp = location.timestamp
    let speed = Self.nonnegativeFinite(location.speed)

    let distance: Double?
    let duration: TimeInterval?
    if let directDestination {
      distance = CLLocationCoordinate2DIsValid(directDestination)
        ? Self.nonnegativeFinite(location.distance(from: CLLocation(latitude: directDestination.latitude,
                                                                    longitude: directDestination.longitude)))
        : nil
      let averageSpeed = movingAverage(speed: speed, timestamp: location.timestamp, now: now)
      if let distance, let averageSpeed {
        let estimate = distance / averageSpeed
        duration = estimate.isFinite && estimate <= Constants.maximumDirectETA ? estimate : nil
      } else {
        duration = nil
      }
    } else {
      distance = Self.nonnegativeFinite(routeDistance)
      if let distance, let routeDuration = Self.nonnegativeFinite(routeDuration), routeDuration > 0 || distance == 0 {
        duration = routeDuration
      } else {
        duration = nil
      }
    }

    let arrival = duration.map { now.addingTimeInterval($0) }
    let finiteArrival = arrival?.timeIntervalSinceReferenceDate.isFinite == true ? arrival : nil
    return Snapshot(speedMetersPerSecond: speed,
                    distanceMeters: distance,
                    remainingTime: finiteArrival == nil ? nil : duration,
                    arrivalDate: finiteArrival)
  }

  private mutating func movingAverage(speed: CLLocationSpeed?, timestamp: Date, now: Date) -> Double? {
    guard let speed, speed >= Constants.minimumMovingSpeed else {
      speedSamples.removeAll(keepingCapacity: true)
      return nil
    }
    speedSamples.removeAll { now.timeIntervalSince($0.timestamp) > Constants.speedWindow }
    // Re-reading the same GPS fix on a UI timer must not create extra speed samples.
    if speedSamples.last?.timestamp != timestamp {
      speedSamples.append(SpeedSample(timestamp: timestamp, metersPerSecond: speed))
    }
    guard speedSamples.count >= Constants.minimumSpeedSampleCount,
          let first = speedSamples.first,
          timestamp.timeIntervalSince(first.timestamp) >= Constants.minimumSpeedSampleSpan else {
      return nil
    }
    let average = speedSamples.reduce(0) { $0 + $1.metersPerSecond / Double(speedSamples.count) }
    return average.isFinite && average >= Constants.minimumMovingSpeed ? average : nil
  }

  private static func isUsable(_ location: CLLocation, now: Date) -> Bool {
    let age = now.timeIntervalSince(location.timestamp)
    return age.isFinite && age >= -Constants.maximumFutureLocationOffset && age <= Constants.maximumLocationAge &&
      location.horizontalAccuracy.isFinite && location.horizontalAccuracy >= 0 &&
      location.horizontalAccuracy <= Constants.maximumHorizontalAccuracy && CLLocationCoordinate2DIsValid(location.coordinate)
  }

  private static func nonnegativeFinite(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
  }
}
