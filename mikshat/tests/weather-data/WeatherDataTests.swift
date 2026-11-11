import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private enum TestFailure: Error { case assertion(String) }

private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw TestFailure.assertion(message) }
}

private func expectError(_ error: MikshatWeatherError, _ operation: () throws -> Void) throws {
  do { try operation(); throw TestFailure.assertion("Expected \(error)") }
  catch let actual as MikshatWeatherError { try expect(actual == error, "Wrong error: \(actual)") }
}

private final class Clock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date
  init(_ date: Date) { self.date = date }
  func read() -> Date { lock.lock(); defer { lock.unlock() }; return date }
  func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(seconds) }
}

private actor FixtureClient: MikshatWeatherClient {
  enum Behavior: Equatable {
    case success, failure, delayed, wrongCoordinate, rateLimited, held
    case invalidCurrentTime, invalidHourlyTime, invalidFetchedAt
  }
  private let original: MikshatWeatherSnapshot
  private var behavior: Behavior = .success
  private(set) var count = 0
  private var held: CheckedContinuation<Void, Never>?
  init(_ snapshot: MikshatWeatherSnapshot) { original = snapshot }
  func set(_ behavior: Behavior) { self.behavior = behavior }
  func release() { held?.resume(); held = nil }
  func fetch(for coordinate: MikshatWeatherCoordinate, now: Date) async throws -> MikshatWeatherSnapshot {
    count += 1
    switch behavior {
    case .failure: throw URLError(.notConnectedToInternet)
    case .rateLimited: throw MikshatWeatherError.rateLimited(until: now.addingTimeInterval(120))
    case .delayed, .wrongCoordinate: try await Task.sleep(nanoseconds: 80_000_000)
    case .held: await withCheckedContinuation { held = $0 }
    case .success, .invalidCurrentTime, .invalidHourlyTime, .invalidFetchedAt: break
    }
    let resultCoordinate = behavior == .wrongCoordinate ? MikshatWeatherCoordinate(latitude: 0, longitude: 0) : coordinate
    let invalidDate = Date(timeIntervalSince1970: 1e20)
    func invalidTime(_ sample: MikshatWeatherSample) -> MikshatWeatherSample {
      MikshatWeatherSample(time: invalidDate, temperatureC: sample.temperatureC, windSpeedKmh: sample.windSpeedKmh,
                           windDirectionDegrees: sample.windDirectionDegrees, windGustsKmh: sample.windGustsKmh,
                           weatherCode: sample.weatherCode, isDay: sample.isDay)
    }
    return MikshatWeatherSnapshot(
      coordinate: resultCoordinate, fetchedAt: behavior == .invalidFetchedAt ? invalidDate : now,
      timeZoneIdentifier: original.timeZoneIdentifier,
      current: behavior == .invalidCurrentTime ? invalidTime(original.current) : original.current,
      hourly: behavior == .invalidHourlyTime ? [invalidTime(original.hourly[0])] : original.hourly)
  }
}

@main
private enum WeatherDataTests {
  static let coordinate = MikshatWeatherCoordinate(latitude: 24.7136, longitude: 46.6753)
  static let now = Date(timeIntervalSince1970: 1_794_432_600)

  static func main() async throws {
    let path = CommandLine.arguments[1]
    let fixture = try Data(contentsOf: URL(fileURLWithPath: path))
    let snapshot = try MikshatWeatherParser.parse(fixture, coordinate: coordinate, fetchedAt: now)
    try parserTests(fixture, snapshot)
    try presentationTests(snapshot)
    try requestTests()
    try await repositoryTests(snapshot)
    try await concurrentValidationTests(snapshot)
    try await resourceAndRetryTests(snapshot)
    try await cachedDateValidationTests(snapshot)
    print("PASS: weather parser, units, missing values, WMO/day/night, wind, UTC/DST, per-site bounded atomic cache, freshness, offline retention, dedupe and retries")
  }

  static func modified(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    change(&object)
    return try JSONSerialization.data(withJSONObject: object)
  }

  static func parserTests(_ fixture: Data, _ snapshot: MikshatWeatherSnapshot) throws {
    try expect(snapshot.current.temperatureC == 22.5, "Current temperature")
    try expect(snapshot.current.windDirectionDegrees == 0, "API bearing must normalize")
    try expect(snapshot.current.weatherCode == 0 && snapshot.current.isDay == false, "Persist raw WMO/day metadata")
    try expect(snapshot.hourly.count == 72, "All source hours retained")
    let first = snapshot.futureHours(at: snapshot.current.time)
    try expect(first.count == 12, "Exactly first twelve future hours")
    try expect(first.map(\.time) == Array(snapshot.hourly[22..<34]).map(\.time), "No cherry picking")
    try expect(first[1].temperatureC == nil, "Null temperature stays missing; hour retained")
    try expect(first[2].isDay == nil, "Unknown day/night remains unknown")
    let equal = snapshot.futureHours(at: snapshot.hourly[22].time)
    try expect(equal.first?.time == snapshot.hourly[23].time, "Exclude hour exactly equal to now")
    try expect(snapshot.futureHours(at: snapshot.hourly[69].time).count == 2, "Old cache shows remaining hours")
    try expect(snapshot.futureHours(at: snapshot.hourly[71].time).isEmpty, "Expired cache has no future hours")
    try expect(snapshot.futureHours(at: now, limit: -1).isEmpty, "Negative limit safe")
    try expect(snapshot.isFresh(at: now.addingTimeInterval(899)), "Fresh before fifteen minutes")
    try expect(!snapshot.isFresh(at: now.addingTimeInterval(900)), "Stale at fifteen minutes")
    try expect(!snapshot.isFresh(at: now.addingTimeInterval(-1)), "Future fetched time not fresh")
    let wrongUnits = try modified(fixture) { object in
      var units = object["hourly_units"] as! [String: String]
      units["wind_speed_10m"] = "m/s"; object["hourly_units"] = units
    }
    try expectError(.incompatibleUnits) { _ = try MikshatWeatherParser.parse(wrongUnits, coordinate: coordinate, fetchedAt: now) }
    let wrongTimeUnits = try modified(fixture) { object in
      var units = object["current_units"] as! [String: String]
      units["time"] = "iso8601"; object["current_units"] = units
    }
    try expectError(.incompatibleUnits) { _ = try MikshatWeatherParser.parse(wrongTimeUnits, coordinate: coordinate, fetchedAt: now) }
    let mismatched = try modified(fixture) { object in
      var hours = object["hourly"] as! [String: Any]
      hours["weather_code"] = [0]; object["hourly"] = hours
    }
    try expectError(.inconsistentHours) { _ = try MikshatWeatherParser.parse(mismatched, coordinate: coordinate, fetchedAt: now) }
    let outOfOrder = try modified(fixture) { object in
      var hours = object["hourly"] as! [String: Any]
      var times = hours["time"] as! [Double]; times[2] = times[1]
      hours["time"] = times; object["hourly"] = hours
    }
    try expectError(.inconsistentHours) { _ = try MikshatWeatherParser.parse(outOfOrder, coordinate: coordinate, fetchedAt: now) }
    let missingFields = try modified(fixture) { object in
      var hours = object["hourly"] as! [String: Any]; hours.removeValue(forKey: "wind_gusts_10m")
      object["hourly"] = hours
      var current = object["current"] as! [String: Any]; current["is_day"] = 2; current["wind_speed_10m"] = -2
      object["current"] = current
    }
    let missing = try MikshatWeatherParser.parse(missingFields, coordinate: coordinate, fetchedAt: now)
    try expect(missing.hourly.allSatisfy { $0.windGustsKmh == nil }, "Missing gust array remains missing")
    try expect(missing.current.isDay == nil && missing.current.windSpeedKmh == nil, "Invalid numeric fields neutral")
    try expectError(.responseTooLarge) {
      _ = try MikshatWeatherParser.parse(fixture, coordinate: coordinate, fetchedAt: now, maximumBytes: 4)
    }
    try expectError(.invalidResponse) {
      _ = try MikshatWeatherParser.parse(Data("{\"temperature_2m\":NaN}".utf8), coordinate: coordinate, fetchedAt: now)
    }
    try expectError(.invalidCoordinate) {
      _ = try MikshatWeatherParser.parse(fixture, coordinate: .init(latitude: .nan, longitude: 0), fetchedAt: now)
    }
    let encoded = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(MikshatWeatherSnapshot.self, from: encoded)
    try expect(decoded == snapshot, "Cache roundtrip retains raw codes/day/time/timezone")
  }

  static func presentationTests(_ snapshot: MikshatWeatherSnapshot) throws {
    let known = [0,1,2,3,45,48,51,53,55,56,57,61,63,65,66,67,71,73,75,77,80,81,82,85,86,95,96,99]
    for code in known {
      let day = MikshatWeatherCondition(code: code, isDay: true)
      let night = MikshatWeatherCondition(code: code, isDay: false)
      let unknown = MikshatWeatherCondition(code: code, isDay: nil)
      try expect(!day.localizationKey.hasSuffix("_unknown") && !night.symbolName.isEmpty, "WMO \(code) mapped")
      try expect(!unknown.symbolName.contains("sun") && !unknown.symbolName.contains("moon"), "Missing is_day neutral")
    }
    try expect(MikshatWeatherCondition(code: 0, isDay: false).symbolName == "moon.stars.fill", "Clear night")
    try expect(MikshatWeatherCondition(code: 2, isDay: true).symbolName == "cloud.sun.fill", "Partly cloudy day")
    try expect(MikshatWeatherCondition(code: 777, isDay: true).localizationKey.hasSuffix("_unknown"), "Unknown WMO neutral")
    try expect(MikshatWeatherCondition(code: nil, isDay: nil).symbolName == "questionmark.circle", "Missing WMO neutral")
    let names = ["n","ne","e","se","s","sw","w","nw"]
    for index in 0..<8 {
      let wind = MikshatWeatherWind(speedKmh: 20, directionDegrees: Double(index * 45))
      try expect(wind.localizationKey == "mikshat_weather_wind_" + names[index], "Eight source directions")
      try expect(wind.bearingDegrees == Double(index * 45), "Source arrow bearing, no 180 degree reversal")
    }
    try expect(MikshatWeatherWind(speedKmh: 1, directionDegrees: -45).bearingDegrees == 315, "Negative direction")
    try expect(MikshatWeatherWind(speedKmh: 1, directionDegrees: 720).bearingDegrees == 0, "Wrapped direction")
    try expect(MikshatWeatherWind(speedKmh: 1, directionDegrees: 22.5).localizationKey.hasSuffix("_ne"), "Half-sector boundary")
    try expect(MikshatWeatherWind(speedKmh: 0, directionDegrees: 90).bearingDegrees == nil, "Calm has no invented direction")
    try expect(MikshatWeatherWind(speedKmh: nil, directionDegrees: 90).bearingDegrees == nil, "Missing speed neutral")
    try expect(MikshatWeatherWind(speedKmh: 2, directionDegrees: .nan).bearingDegrees == nil, "Non-finite bearing neutral")
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = snapshot.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    try expect(formatter.string(from: snapshot.current.time) == "2026-11-12 00:30", "Unix time uses site zone once, crosses midnight")
    formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
    let iso = ISO8601DateFormatter()
    let before = iso.date(from: "2026-10-25T00:00:00Z")!
    let after = before.addingTimeInterval(3600)
    formatter.dateFormat = "yyyy-MM-dd HH:mm Z"
    try expect(formatter.string(from: before) == "2026-10-25 02:00 +0200", "DST first absolute hour")
    try expect(formatter.string(from: after) == "2026-10-25 02:00 +0100", "DST repeated local hour remains distinct")
  }

  static func requestTests() throws {
    let request = try MikshatOpenMeteoClient().request(for: coordinate)
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
    let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })
    try expect(components.scheme == "https" && components.host == "api.open-meteo.com", "Public keyless HTTPS host")
    try expect(items["latitude"] == String(coordinate.latitude) && items["longitude"] == String(coordinate.longitude), "Selected coordinates")
    try expect(items["current"] == items["hourly"] && items["hourly"]!.split(separator: ",").count == 6, "All six fields")
    try expect(items["temperature_unit"] == "celsius" && items["wind_speed_unit"] == "kmh", "Explicit physical units")
    try expect(items["timezone"] == "auto" && items["timeformat"] == "unixtime" && items["forecast_days"] == "3", "Absolute times, automatic site timezone, three days")
    try expect(items["apikey"] == nil, "No API key")
    try expect(MikshatOpenMeteoClient.retryAfter("120", now: now) == now.addingTimeInterval(120), "Retry-After seconds")
    let date = "Wed, 11 Nov 2026 22:00:00 GMT"
    try expect(MikshatOpenMeteoClient.retryAfter(date, now: now) == Date(timeIntervalSince1970: 1_794_434_400), "Retry-After HTTP date")
    try expect(MikshatOpenMeteoClient.retryAfter("NaN", now: now) == nil, "Invalid retry delay")
    try expect(coordinate.distance(to: .init(latitude: coordinate.latitude + 0.0001, longitude: coordinate.longitude)) < 25, "Tolerance in meters")
  }

  static func concurrentValidationTests(_ snapshot: MikshatWeatherSnapshot) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = FixtureClient(snapshot)
    await client.set(.wrongCoordinate)
    let repository = MikshatWeatherRepository(cacheDirectory: directory, client: client, now: { now })
    @Sendable func rejected() async -> Bool {
      do { _ = try await repository.refresh(for: coordinate); return false }
      catch MikshatWeatherError.invalidResponse { return true }
      catch { return false }
    }
    async let a = rejected()
    async let b = rejected()
    let results = await (a, b)
    try expect(results.0 && results.1, "All deduplicated callers validate the shared site's response")
    try expect(await client.count == 1, "Invalid shared response still deduplicated")
    try expect(await repository.cached(for: coordinate) == nil, "Invalid site data never enters cache")
  }

  static func resourceAndRetryTests(_ snapshot: MikshatWeatherSnapshot) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = FixtureClient(snapshot)
    let clock = Clock(now)
    var configuration = MikshatWeatherConfiguration()
    configuration.maximumConcurrentRequests = 1
    let repository = MikshatWeatherRepository(cacheDirectory: directory, configuration: configuration,
                                              client: client, now: { clock.read() })
    await client.set(.held)
    let first = Task { try await repository.refresh(for: coordinate) }
    while await client.count == 0 { await Task.yield() }
    let other = MikshatWeatherCoordinate(latitude: 21.42, longitude: 39.82)
    do { _ = try await repository.refresh(for: other); throw TestFailure.assertion("Request bound required") }
    catch MikshatWeatherError.requestLimit { }
    await client.release()
    let firstSnapshot = try await first.value
    await client.set(.rateLimited)
    do { _ = try await repository.refresh(for: coordinate, force: true); throw TestFailure.assertion("429 expected") }
    catch MikshatWeatherError.rateLimited(until: _) { }
    let count = await client.count
    do { _ = try await repository.refresh(for: other, force: true); throw TestFailure.assertion("Global retry expected") }
    catch let MikshatWeatherError.rateLimited(until: date) {
      try expect(date == clock.read().addingTimeInterval(120), "Provider Retry-After shared across sites")
    }
    try expect(await client.count == count, "Retry-After does not issue a new network request")
    try expect(await repository.cached(for: coordinate) == firstSnapshot, "429 preserves the last valid site data")
    clock.advance(121)
    await client.set(.success)
    _ = try await repository.refresh(for: other)
    configuration.maximumCacheBytes = 512
    let boundedDirectory = directory.appendingPathComponent("tiny-cache")
    let bounded = MikshatWeatherRepository(cacheDirectory: boundedDirectory, configuration: configuration,
                                          client: client, now: { clock.read() })
    _ = try await bounded.refresh(for: coordinate)
    let bytes = try Data(contentsOf: boundedDirectory.appendingPathComponent("weather-v1.json"))
    try expect(bytes.count <= 512, "Encoded cache byte budget enforced independently of site count")
    _ = try JSONSerialization.jsonObject(with: bytes)
  }

  static func cachedDateValidationTests(_ snapshot: MikshatWeatherSnapshot) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let clock = Clock(now)
    let client = FixtureClient(snapshot)
    let repository = MikshatWeatherRepository(cacheDirectory: directory, client: client, now: { clock.read() })
    let valid = try await repository.refresh(for: coordinate)
    let diskURL = directory.appendingPathComponent("weather-v1.json")
    let validDisk = try Data(contentsOf: diskURL)

    for field in ["current", "hourly", "fetchedAt", "lastAccessed"] {
      var object = try JSONSerialization.jsonObject(with: validDisk) as! [String: Any]
      var entries = object["entries"] as! [String: Any]
      var entry = entries[coordinate.cacheKey] as! [String: Any]
      var stored = entry["snapshot"] as! [String: Any]
      if field == "lastAccessed" {
        entry[field] = 1e20
      } else if field == "fetchedAt" {
        stored[field] = 1e20
      } else if field == "current" {
        var current = stored[field] as! [String: Any]
        current["time"] = 1e20
        stored[field] = current
      } else {
        var hour = (stored[field] as! [[String: Any]])[0]
        hour["time"] = 1e20
        // One hour is already sorted, so date validation must reject it independently of ordering.
        stored[field] = [hour]
      }
      entry["snapshot"] = stored
      entries[coordinate.cacheKey] = entry
      object["entries"] = entries
      try JSONSerialization.data(withJSONObject: object).write(to: diskURL, options: .atomic)
      let corrupt = MikshatWeatherRepository(cacheDirectory: directory, client: client, now: { clock.read() })
      try expect(await corrupt.cached(for: coordinate) == nil, "Out-of-range cached \(field) date rejected")
    }
    try validDisk.write(to: diskURL, options: .atomic)

    for behavior in [FixtureClient.Behavior.invalidCurrentTime, .invalidHourlyTime, .invalidFetchedAt] {
      clock.advance(31)
      await client.set(behavior)
      do {
        _ = try await repository.refresh(for: coordinate, force: true)
        throw TestFailure.assertion("Invalid client date must be rejected")
      } catch MikshatWeatherError.invalidResponse { }
      let reloaded = MikshatWeatherRepository(cacheDirectory: directory, client: client, now: { clock.read() })
      try expect(await reloaded.cached(for: coordinate) == valid, "Invalid client date keeps last valid on disk")
      try expect(await repository.cached(for: coordinate) == valid, "Invalid client date keeps last valid in memory")
    }
  }

  static func repositoryTests(_ snapshot: MikshatWeatherSnapshot) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let clock = Clock(now)
    let client = FixtureClient(snapshot)
    var configuration = MikshatWeatherConfiguration()
    configuration.maximumLocations = 2
    let repository = MikshatWeatherRepository(cacheDirectory: directory, configuration: configuration,
                                              client: client, now: { clock.read() })
    let empty = await repository.cached(for: coordinate)
    try expect(empty == nil, "No global last-location cache")
    let first = try await repository.refresh(for: coordinate)
    try expect(first.coordinate == coordinate, "Fetch selected site")
    let cached = await repository.cached(for: coordinate)
    try expect(cached == first, "Immediate matching cache")
    let other = MikshatWeatherCoordinate(latitude: 21.42, longitude: 39.82)
    let wrong = await repository.cached(for: other)
    try expect(wrong == nil, "Never reuse another city's weather")
    let near = MikshatWeatherCoordinate(latitude: coordinate.latitude + 0.00009, longitude: coordinate.longitude)
    try expect(await repository.cached(for: near) != nil, "Near-coordinate tolerance lookup")
    _ = try await repository.refresh(for: coordinate)
    try expect(await client.count == 1, "Fresh cache avoids duplicate request")
    clock.advance(901)
    await client.set(.failure)
    do { _ = try await repository.refresh(for: coordinate); throw TestFailure.assertion("Offline must fail") }
    catch is URLError { }
    let retained = await repository.cached(for: coordinate)
    try expect(retained == first && !retained!.isFresh(at: clock.read()), "Offline preserves aged last valid response")
    let countAfterFailure = await client.count
    do { _ = try await repository.refresh(for: coordinate, force: true); throw TestFailure.assertion("Backoff required") }
    catch let error as MikshatWeatherError {
      if case .rateLimited = error { } else { throw error }
    }
    try expect(await client.count == countAfterFailure, "Force refresh respects retry delay")
    let reloaded = MikshatWeatherRepository(cacheDirectory: directory, configuration: configuration,
                                           client: client, now: { clock.read() })
    try expect(await reloaded.cached(for: coordinate) == first, "Atomic disk persists WMO/day/time/site metadata")
    clock.advance(31)
    await client.set(.delayed)
    async let a = repository.refresh(for: coordinate, force: true)
    async let b = repository.refresh(for: coordinate, force: true)
    let pair = try await (a, b)
    let deduplicatedCount = await client.count
    try expect(pair.0 == pair.1 && deduplicatedCount == countAfterFailure + 1, "Concurrent same-site requests deduplicated")
    await client.set(.success)
    clock.advance(1)
    _ = try await repository.refresh(for: other, force: true)
    clock.advance(1)
    _ = try await repository.refresh(for: coordinate)
    clock.advance(1)
    let third = MikshatWeatherCoordinate(latitude: 28.4, longitude: 36.6)
    _ = try await repository.refresh(for: third, force: true)
    try expect(await repository.cached(for: other) == nil, "Least recently used site evicted")
    try expect(await repository.cached(for: coordinate) != nil, "Fresh refresh also updates LRU access")
    let diskURL = directory.appendingPathComponent("weather-v1.json")
    let disk = try Data(contentsOf: diskURL)
    try expect(disk.count <= configuration.maximumCacheBytes, "Finite cache bytes")
    let object = try JSONSerialization.jsonObject(with: disk) as! [String: Any]
    try expect((object["entries"] as! [String: Any]).count == 2, "Bounded site count")
    try Data("broken-cache".utf8).write(to: diskURL, options: .atomic)
    let corrupt = MikshatWeatherRepository(cacheDirectory: directory, client: client)
    try expect(await corrupt.cached(for: coordinate) == nil, "Damaged weather cache safe miss")
  }
}
