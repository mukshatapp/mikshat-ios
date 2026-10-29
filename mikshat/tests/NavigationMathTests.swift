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
    check(!math.usesGPS(mode: 0, speed: 30), "Sensor preference")
    check(math.usesGPS(mode: 1, speed: 0), "GPS preference")
    check(!math.usesGPS(mode: 2, speed: 9.9 / 3.6), "Auto below threshold")
    check(math.usesGPS(mode: 2, speed: 10 / 3.6), "Auto at threshold")
    print("PASS: Qibla reference vectors, Arabic DDM, invalid/boundary coordinates, rollover, heading threshold")
  }
}
