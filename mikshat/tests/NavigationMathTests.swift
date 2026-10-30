import Foundation

@main
struct NavigationMathTests {
  static func main() throws {
    func check(_ condition: Bool, _ message: String) {
      precondition(condition, message)
    }
    let math = MikshatNavigationMath.self
    let riyadh = math.bearing(latitude: 24.7136, longitude: 46.6753)
    check(abs(riyadh - 243.8) < 0.2, "Riyadh Qibla bearing")
    check(abs(math.bearing(latitude: 0, longitude: 0, targetLatitude: 10, targetLongitude: 0)) < 0.0001,
          "Due north")
    check(abs(math.bearing(latitude: 0, longitude: 0, targetLatitude: 0, targetLongitude: 10) - 90) < 0.0001,
          "Due east")
    check(math.minuteInput("٢٠٣٨٨") == "20.388", "Automatic Arabic minute input")
    let lat = try math.coordinate(degrees: "٢٤", minutes: "٤٢٫٨١٠", latitude: true)
    check(abs(lat - 24.7135) < 0.000001, "Arabic DDM")
    let lon = try math.coordinate(degrees: "046", minutes: "40.518", latitude: false, negative: true)
    check(abs(lon + 46.6753) < 0.000001, "Western longitude")
    for (degrees, minutes, latitude) in [("91", "00.000", true), ("180", "00.001", false),
                                          ("24", "60.000", true), ("24", "ab.cd", true)] {
      do {
        _ = try math.coordinate(degrees: degrees, minutes: minutes, latitude: latitude)
        preconditionFailure("Invalid coordinate accepted")
      } catch {}
    }
    check(math.ddm(24.99999999, latitude: true) == "N 25° 00.000′", "DDM minute rollover")
    check(math.ddm(0, latitude: true) == "N 00° 00.000′", "DDM zero padding")
    check(math.ddm(-46.6753, latitude: false) == "W 046° 40.518′", "DDM west and fractional minutes")
    check(!math.usesGPS(mode: 0, speed: 30), "Sensor preference")
    check(math.usesGPS(mode: 1, speed: 0), "GPS preference")
    check(!math.usesGPS(mode: 2, speed: 9.9 / 3.6), "Auto below threshold")
    check(math.usesGPS(mode: 2, speed: 10 / 3.6), "Auto at threshold")
    let northPole = try math.coordinate(degrees: "90", minutes: "00.000", latitude: true)
    let dateLine = try math.coordinate(degrees: "180", minutes: "00.000", latitude: false)
    check(northPole == 90 && dateLine == 180, "Exact coordinate limits")
    check(math.dms(24.999999999, latitude: true) == "N 25° 00′ 00.00″", "DMS second/minute rollover")
    check(math.dms(-47.125, latitude: false) == "W 047° 07′ 30.00″", "DMS west")
    let pairs = math.coordinatePairs(latitude: 24.3003, longitude: 47.125917)
    check(pairs.count == 3 && pairs.allSatisfy { !$0.isEmpty }, "Three complete coordinate copy values")
    check(pairs[0] == "24.300300, 47.125917", "Decimal pair precision")
    check(pairs[1].contains("N ") && pairs[1].contains("E ") && pairs[1].contains("\n"), "DDM pair contains both components")
    var estimate = MikshatTravelEstimate()
    check(estimate.update(distance: 1000, speed: 0, timestamp: 100, now: 100) == nil, "No ETA while stopped")
    check(estimate.update(distance: 1000, speed: 10, timestamp: 101, now: 101) == 100, "Travel estimate from movement")
    check(estimate.update(distance: 1000, speed: 30, timestamp: 102, now: 102) == 50, "Mean speed estimate")
    check(estimate.update(distance: 1000, speed: 30, timestamp: 102, now: 103) == 50, "Repeated GPS fix is not sampled twice")
    check(estimate.update(distance: 1000, speed: 30, timestamp: 102, now: 120) == nil, "Stale fix has no ETA")
    check(estimate.update(distance: 5, speed: 0, timestamp: 121, now: 121) == 0, "Arrival near destination")
    print("PASS: Qibla, DD/DDM/DMS, Arabic input, coordinate limits/rollover, heading threshold and travel estimates")
  }
}
