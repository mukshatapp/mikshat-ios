import Foundation

// One opt-in request for a public reference coordinate, never a user's GPS fix.
@main
struct WeatherLiveProbe {
  static func main() async throws {
    let coordinate = MikshatWeatherCoordinate(latitude: 24.7136, longitude: 46.6753)
    let snapshot = try await MikshatOpenMeteoClient().fetch(for: coordinate, now: Date())
    let hours = snapshot.futureHours(at: Date())
    guard hours.count == 12, snapshot.timeZoneIdentifier == "Asia/Riyadh",
          snapshot.coordinate == coordinate else {
      throw NSError(domain: "MikshatWeatherLiveProbe", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Live response did not meet forecast/site/timezone requirements"])
    }
    let report: [String: Any] = ["source": "Open-Meteo free public API", "live": true,
      "site": "public Riyadh reference coordinate", "futureHours": hours.count,
      "timezone": snapshot.timeZoneIdentifier, "cacheOrHardwareGps": false]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
}
