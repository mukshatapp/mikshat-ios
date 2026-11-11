import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private enum MikshatWeatherTime {
  static func isValid(_ unixTime: Double) -> Bool {
    unixTime.isFinite && unixTime >= 0 && unixTime <= 253_402_300_799
  }
}

struct MikshatWeatherCoordinate: Codable, Hashable, Sendable {
  let latitude: Double
  let longitude: Double

  var isValid: Bool {
    latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
  }

  // Four decimal places are about 11 m of latitude. Every hit also checks the original request within 25 m.
  var cacheKey: String {
    String(format: "%.4f,%.4f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
  }

  func distance(to other: Self) -> Double {
    let a = latitude * .pi / 180
    let b = other.latitude * .pi / 180
    let dLat = (other.latitude - latitude) * .pi / 180
    let dLon = (other.longitude - longitude) * .pi / 180
    let h = pow(sin(dLat / 2), 2) + cos(a) * cos(b) * pow(sin(dLon / 2), 2)
    return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
  }
}

struct MikshatWeatherSample: Codable, Equatable, Sendable {
  let time: Date
  let temperatureC: Double?
  let windSpeedKmh: Double?
  let windDirectionDegrees: Double?
  let windGustsKmh: Double?
  let weatherCode: Int?
  let isDay: Bool?

  fileprivate var isValid: Bool {
    MikshatWeatherTime.isValid(time.timeIntervalSince1970) &&
      [temperatureC, windSpeedKmh, windDirectionDegrees, windGustsKmh].allSatisfy { $0?.isFinite ?? true } &&
      (windSpeedKmh.map { $0 >= 0 } ?? true) && (windGustsKmh.map { $0 >= 0 } ?? true)
  }
}

struct MikshatWeatherSnapshot: Codable, Equatable, Sendable {
  let coordinate: MikshatWeatherCoordinate
  let fetchedAt: Date
  let timeZoneIdentifier: String
  let current: MikshatWeatherSample
  let hourly: [MikshatWeatherSample]

  var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)! }

  func futureHours(at now: Date = Date(), limit: Int = 12) -> [MikshatWeatherSample] {
    Array(hourly.lazy.filter { $0.time > now }.prefix(max(0, limit)))
  }

  func isFresh(at now: Date = Date()) -> Bool {
    isFresh(at: now, freshness: 15 * 60)
  }

  fileprivate func isFresh(at now: Date, freshness: TimeInterval) -> Bool {
    let age = now.timeIntervalSince(fetchedAt)
    return age >= 0 && age < freshness
  }

  fileprivate var isValid: Bool {
    coordinate.isValid && MikshatWeatherTime.isValid(fetchedAt.timeIntervalSince1970) &&
      TimeZone(identifier: timeZoneIdentifier) != nil && current.isValid &&
      !hourly.isEmpty && hourly.count <= 96 && hourly.allSatisfy(\.isValid) &&
      zip(hourly, hourly.dropFirst()).allSatisfy { $0.time < $1.time }
  }
}

struct MikshatWeatherConfiguration: Sendable {
  var freshness: TimeInterval = 15 * 60
  var maximumLocations = 20
  var maximumCacheBytes = 2 * 1024 * 1024
  var maximumResponseBytes = 512 * 1024
  var maximumConcurrentRequests = 4
  var requestTimeout: TimeInterval = 20
  var minimumRetryDelay: TimeInterval = 30
  var matchingDistanceMeters: Double = 25
}

enum MikshatWeatherError: Error, Equatable {
  case invalidCoordinate
  case invalidResponse
  case incompatibleUnits
  case inconsistentHours
  case responseTooLarge
  case httpStatus(Int)
  case rateLimited(until: Date)
  case requestLimit
}

protocol MikshatWeatherClient: Sendable {
  func fetch(for coordinate: MikshatWeatherCoordinate, now: Date) async throws -> MikshatWeatherSnapshot
}

struct MikshatOpenMeteoClient: MikshatWeatherClient {
  let configuration: MikshatWeatherConfiguration

  init(configuration: MikshatWeatherConfiguration = .init()) {
    self.configuration = configuration
  }

  func request(for coordinate: MikshatWeatherCoordinate) throws -> URLRequest {
    guard coordinate.isValid else { throw MikshatWeatherError.invalidCoordinate }
    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    let fields = "temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,weather_code,is_day"
    components.queryItems = [
      URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
      URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
      URLQueryItem(name: "current", value: fields), URLQueryItem(name: "hourly", value: fields),
      URLQueryItem(name: "temperature_unit", value: "celsius"),
      URLQueryItem(name: "wind_speed_unit", value: "kmh"), URLQueryItem(name: "timeformat", value: "unixtime"),
      URLQueryItem(name: "timezone", value: "auto"), URLQueryItem(name: "forecast_days", value: "3")
    ]
    var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData,
                             timeoutInterval: configuration.requestTimeout)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  func fetch(for coordinate: MikshatWeatherCoordinate, now: Date) async throws -> MikshatWeatherSnapshot {
    let startedAt = ProcessInfo.processInfo.systemUptime
    let (data, response) = try await MikshatWeatherBoundedRequest.load(
      request: request(for: coordinate), maximumBytes: configuration.maximumResponseBytes)
    let receivedAt = now.addingTimeInterval(max(0, ProcessInfo.processInfo.systemUptime - startedAt))
    guard (200...299).contains(response.statusCode) else {
      if let date = Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: receivedAt) {
        throw MikshatWeatherError.rateLimited(until: date)
      }
      if response.statusCode == 429 {
        throw MikshatWeatherError.rateLimited(until: receivedAt.addingTimeInterval(60))
      }
      throw MikshatWeatherError.httpStatus(response.statusCode)
    }
    return try MikshatWeatherParser.parse(data, coordinate: coordinate, fetchedAt: receivedAt,
                                          maximumBytes: configuration.maximumResponseBytes)
  }

  static func retryAfter(_ value: String?, now: Date) -> Date? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
    if let seconds = Double(value), seconds.isFinite, seconds >= 0 {
      let date = now.addingTimeInterval(seconds)
      return date.timeIntervalSince1970.isFinite ? max(now, date) : nil
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: value).map { max(now, $0) }
  }
}

// The delegate stops receiving at the byte limit, before constructing an unbounded Data response.
private final class MikshatWeatherBoundedRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var response: HTTPURLResponse?
  private var data = Data()
  private var cancelled = false
  private let maximumBytes: Int

  private init(maximumBytes: Int) { self.maximumBytes = max(1, maximumBytes) }

  static func load(request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
    let loader = MikshatWeatherBoundedRequest(maximumBytes: maximumBytes)
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in loader.start(request, continuation) }
    }, onCancel: { loader.cancel() })
  }

  private func start(_ request: URLRequest, _ continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) {
    lock.lock()
    if cancelled {
      lock.unlock()
      continuation.resume(throwing: CancellationError())
      return
    }
    self.continuation = continuation
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.timeoutIntervalForRequest = request.timeoutInterval
    configuration.timeoutIntervalForResource = request.timeoutInterval + 5
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    self.session = session
    let task = session.dataTask(with: request)
    self.task = task
    lock.unlock()
    task.resume()
  }

  private func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
    finish(.failure(CancellationError()))
  }

  private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    let session = self.session
    self.session = nil
    let task = self.task
    self.task = nil
    lock.unlock()
    task?.cancel()
    session?.invalidateAndCancel()
    continuation?.resume(with: result)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                  completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard let httpResponse = response as? HTTPURLResponse else {
      completionHandler(.cancel)
      finish(.failure(MikshatWeatherError.invalidResponse))
      return
    }
    guard response.expectedContentLength <= Int64(maximumBytes) else {
      completionHandler(.cancel)
      finish(.failure(MikshatWeatherError.responseTooLarge))
      return
    }
    self.response = httpResponse
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard self.data.count <= maximumBytes - data.count else {
      finish(.failure(MikshatWeatherError.responseTooLarge))
      return
    }
    self.data.append(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error { finish(.failure(error)) }
    else if let response = response { finish(.success((data, response))) }
    else { finish(.failure(MikshatWeatherError.invalidResponse)) }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    // Keep this public, keyless endpoint on HTTPS and its configured host.
    completionHandler(request.url?.scheme == "https" && request.url?.host == "api.open-meteo.com" ? request : nil)
  }
}

enum MikshatWeatherParser {
  private struct Values: Decodable {
    let time: Double?
    let temperature_2m: Double?
    let wind_speed_10m: Double?
    let wind_direction_10m: Double?
    let wind_gusts_10m: Double?
    let weather_code: Double?
    let is_day: Double?
  }

  private struct Hours: Decodable {
    let time: [Double]
    let temperature_2m: [Double?]?
    let wind_speed_10m: [Double?]?
    let wind_direction_10m: [Double?]?
    let wind_gusts_10m: [Double?]?
    let weather_code: [Double?]?
    let is_day: [Double?]?
  }

  private struct Response: Decodable {
    let timezone: String
    let current_units: [String: String]
    let hourly_units: [String: String]
    let current: Values
    let hourly: Hours
  }

  static func parse(_ data: Data, coordinate: MikshatWeatherCoordinate, fetchedAt: Date,
                    maximumBytes: Int = 512 * 1024) throws -> MikshatWeatherSnapshot {
    guard coordinate.isValid else { throw MikshatWeatherError.invalidCoordinate }
    guard data.count <= maximumBytes else { throw MikshatWeatherError.responseTooLarge }
    let decoded: Response
    do { decoded = try JSONDecoder().decode(Response.self, from: data) }
    catch { throw MikshatWeatherError.invalidResponse }
    guard TimeZone(identifier: decoded.timezone) != nil,
          let currentTime = decoded.current.time, MikshatWeatherTime.isValid(currentTime) else {
      throw MikshatWeatherError.invalidResponse
    }
    let hours = decoded.hourly
    guard !hours.time.isEmpty, hours.time.count <= 96, hours.time.allSatisfy(MikshatWeatherTime.isValid),
          zip(hours.time, hours.time.dropFirst()).allSatisfy({ $1 - $0 == 3600 }) else {
      throw MikshatWeatherError.inconsistentHours
    }
    let arrays = [hours.temperature_2m, hours.wind_speed_10m, hours.wind_direction_10m,
                  hours.wind_gusts_10m, hours.weather_code, hours.is_day]
    guard arrays.allSatisfy({ $0 == nil || $0?.count == hours.time.count }) else {
      throw MikshatWeatherError.inconsistentHours
    }
    let currentFields = [decoded.current.temperature_2m, decoded.current.wind_speed_10m,
                         decoded.current.wind_direction_10m, decoded.current.wind_gusts_10m,
                         decoded.current.weather_code, decoded.current.is_day]
    try validateUnits(decoded.current_units, present: currentFields.map { $0 != nil })
    try validateUnits(decoded.hourly_units, present: arrays.map { $0 != nil })
    let current = sample(time: currentTime, values: currentFields)
    let samples = hours.time.indices.map { index in
      sample(time: hours.time[index], values: arrays.map { $0?[index] ?? nil })
    }
    let snapshot = MikshatWeatherSnapshot(coordinate: coordinate, fetchedAt: fetchedAt,
                                         timeZoneIdentifier: decoded.timezone, current: current, hourly: samples)
    guard snapshot.isValid else { throw MikshatWeatherError.invalidResponse }
    return snapshot
  }

  private static func validateUnits(_ units: [String: String], present: [Bool]) throws {
    guard units["time"] == "unixtime" else { throw MikshatWeatherError.incompatibleUnits }
    let fields = ["temperature_2m", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m", "weather_code", "is_day"]
    let expected = ["°C", "km/h", "°", "km/h", "wmo code", ""]
    for index in fields.indices where present[index] {
      guard units[fields[index]] == expected[index] else { throw MikshatWeatherError.incompatibleUnits }
    }
  }

  private static func sample(time: Double, values: [Double?]) -> MikshatWeatherSample {
    func finite(_ index: Int, nonnegative: Bool = false) -> Double? {
      guard let value = values[index], value.isFinite, !nonnegative || value >= 0 else { return nil }
      return value
    }
    let code = finite(4).flatMap { value -> Int? in
      guard value.rounded() == value, value >= 0, value <= 999 else { return nil }
      return Int(value)
    }
    let day = finite(5).flatMap { $0 == 0 ? false : ($0 == 1 ? true : nil) }
    return MikshatWeatherSample(time: Date(timeIntervalSince1970: time), temperatureC: finite(0),
                               windSpeedKmh: finite(1, nonnegative: true),
                               windDirectionDegrees: finite(2).map(MikshatWeatherWind.normalize),
                               windGustsKmh: finite(3, nonnegative: true), weatherCode: code, isDay: day)
  }
}

actor MikshatWeatherRepository {
  static let shared = MikshatWeatherRepository()

  private struct Entry: Codable {
    let snapshot: MikshatWeatherSnapshot
    var lastAccessed: Date
  }

  private struct DiskCache: Codable {
    let version: Int
    let entries: [String: Entry]
  }

  private struct Request {
    let id: UUID
    let task: Task<MikshatWeatherSnapshot, Error>
  }

  private let configuration: MikshatWeatherConfiguration
  private let client: any MikshatWeatherClient
  private let cacheURL: URL
  private let now: @Sendable () -> Date
  private var entries: [String: Entry] = [:]
  private var requests: [String: Request] = [:]
  private var retryDates: [String: Date] = [:]
  private var globalRetryDate: Date?
  private var loaded = false

  init(cacheDirectory: URL? = nil, configuration: MikshatWeatherConfiguration = .init(),
       client: (any MikshatWeatherClient)? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
    self.configuration = configuration
    self.client = client ?? MikshatOpenMeteoClient(configuration: configuration)
    self.now = now
    let directory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("MikshatWeather", isDirectory: true)
    cacheURL = directory.appendingPathComponent("weather-v1.json")
  }

  func cached(for coordinate: MikshatWeatherCoordinate) -> MikshatWeatherSnapshot? {
    guard coordinate.isValid else { return nil }
    loadIfNeeded()
    guard let key = matchingKey(for: coordinate), var entry = entries[key] else { return nil }
    entry.lastAccessed = now()
    entries[key] = entry
    persist()
    return entry.snapshot
  }

  func refresh(for coordinate: MikshatWeatherCoordinate, force: Bool = false) async throws -> MikshatWeatherSnapshot {
    guard coordinate.isValid else { throw MikshatWeatherError.invalidCoordinate }
    loadIfNeeded()
    let date = now()
    retryDates = retryDates.filter { $0.value > date }
    let key = coordinate.cacheKey
    if let existing = requests[key] { return try await settle(existing, key: key) }
    if !force, let cachedKey = matchingKey(for: coordinate), var entry = entries[cachedKey],
       entry.snapshot.isFresh(at: date, freshness: configuration.freshness) {
      entry.lastAccessed = date
      entries[cachedKey] = entry
      persist()
      return entry.snapshot
    }
    if let deadline = [retryDates[key], globalRetryDate].compactMap({ $0 }).max(), deadline > date {
      throw MikshatWeatherError.rateLimited(until: deadline)
    }
    guard requests.count < max(1, configuration.maximumConcurrentRequests) else {
      throw MikshatWeatherError.requestLimit
    }
    let id = UUID()
    let client = self.client
    // A shared task is independent of any one screen's cancellation; the screen ignores late results after closing.
    let tolerance = configuration.matchingDistanceMeters
    let task = Task.detached {
      let snapshot = try await client.fetch(for: coordinate, now: date)
      guard snapshot.isValid, snapshot.coordinate.distance(to: coordinate) <= tolerance else {
        throw MikshatWeatherError.invalidResponse
      }
      return snapshot
    }
    let request = Request(id: id, task: task)
    requests[key] = request
    return try await settle(request, key: key)
  }

  private func settle(_ request: Request, key: String) async throws -> MikshatWeatherSnapshot {
    do {
      let snapshot = try await request.task.value
      if requests[key]?.id == request.id {
        requests[key] = nil
        retryDates[key] = nil
        entries[key] = Entry(snapshot: snapshot, lastAccessed: now())
        persist()
      }
      return snapshot
    } catch {
      if requests[key]?.id == request.id {
        requests[key] = nil
        retryDates[key] = now().addingTimeInterval(max(1, configuration.minimumRetryDelay))
        while retryDates.count > max(1, configuration.maximumLocations * 2) {
          if let oldest = retryDates.min(by: { $0.value < $1.value })?.key { retryDates[oldest] = nil }
        }
        if case let MikshatWeatherError.rateLimited(until: deadline) = error {
          globalRetryDate = max(globalRetryDate ?? deadline, deadline)
        }
      }
      throw error
    }
  }

  private func matchingKey(for coordinate: MikshatWeatherCoordinate) -> String? {
    entries.filter { $0.value.snapshot.coordinate.distance(to: coordinate) <= configuration.matchingDistanceMeters }
      .min { lhs, rhs in
        lhs.value.snapshot.coordinate.distance(to: coordinate) < rhs.value.snapshot.coordinate.distance(to: coordinate)
      }?.key
  }

  private func loadIfNeeded() {
    guard !loaded else { return }
    loaded = true
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
          let size = attributes[.size] as? NSNumber, size.intValue <= configuration.maximumCacheBytes,
          let data = try? Data(contentsOf: cacheURL), data.count <= configuration.maximumCacheBytes,
          let disk = try? JSONDecoder().decode(DiskCache.self, from: data), disk.version == 1 else { return }
    entries = disk.entries.filter { key, entry in
      entry.snapshot.isValid && entry.snapshot.coordinate.cacheKey == key &&
        MikshatWeatherTime.isValid(entry.lastAccessed.timeIntervalSince1970)
    }
    trim()
  }

  private func trim() {
    while entries.count > max(1, configuration.maximumLocations) {
      guard let key = entries.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })?.key else { break }
      entries[key] = nil
    }
  }

  private func persist() {
    trim()
    var data = try? JSONEncoder().encode(DiskCache(version: 1, entries: entries))
    while let bytes = data, bytes.count > max(1, configuration.maximumCacheBytes), !entries.isEmpty {
      if let key = entries.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })?.key { entries[key] = nil }
      data = try? JSONEncoder().encode(DiskCache(version: 1, entries: entries))
    }
    guard let data = data, data.count <= configuration.maximumCacheBytes else { return }
    do {
      try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                              withIntermediateDirectories: true)
      try data.write(to: cacheURL, options: .atomic)
    } catch {
      // A failed write leaves the preceding atomic disk file intact; valid in-memory data remains available.
    }
  }
}

struct MikshatWeatherCondition {
  let localizationKey: String
  let symbolName: String

  init(code: Int?, isDay: Bool?) {
    let name: String
    let symbol: String
    func daylight(_ day: String, _ night: String, _ neutral: String) -> String {
      isDay.map { $0 ? day : night } ?? neutral
    }
    switch code {
    case 0: name = "clear"; symbol = daylight("sun.max.fill", "moon.stars.fill", "circle")
    case 1: name = "mainly_clear"; symbol = daylight("sun.max.fill", "moon.stars.fill", "cloud.fill")
    case 2: name = "partly_cloudy"; symbol = daylight("cloud.sun.fill", "cloud.moon.fill", "cloud.fill")
    case 3: name = "overcast"; symbol = "cloud.fill"
    case 45: name = "fog"; symbol = "cloud.fog.fill"
    case 48: name = "rime_fog"; symbol = "cloud.fog.fill"
    case 51: name = "drizzle_light"; symbol = "cloud.drizzle.fill"
    case 53: name = "drizzle_moderate"; symbol = "cloud.drizzle.fill"
    case 55: name = "drizzle_dense"; symbol = "cloud.drizzle.fill"
    case 56: name = "freezing_drizzle_light"; symbol = "cloud.sleet.fill"
    case 57: name = "freezing_drizzle_dense"; symbol = "cloud.sleet.fill"
    case 61: name = "rain_light"; symbol = "cloud.rain.fill"
    case 63: name = "rain_moderate"; symbol = "cloud.rain.fill"
    case 65: name = "rain_heavy"; symbol = "cloud.heavyrain.fill"
    case 66: name = "freezing_rain_light"; symbol = "cloud.sleet.fill"
    case 67: name = "freezing_rain_heavy"; symbol = "cloud.sleet.fill"
    case 71: name = "snow_light"; symbol = "cloud.snow.fill"
    case 73: name = "snow_moderate"; symbol = "cloud.snow.fill"
    case 75: name = "snow_heavy"; symbol = "cloud.snow.fill"
    case 77: name = "snow_grains"; symbol = "snowflake"
    case 80: name = "rain_showers_light"; symbol = "cloud.rain.fill"
    case 81: name = "rain_showers_moderate"; symbol = "cloud.rain.fill"
    case 82: name = "rain_showers_violent"; symbol = "cloud.heavyrain.fill"
    case 85: name = "snow_showers_light"; symbol = "cloud.snow.fill"
    case 86: name = "snow_showers_heavy"; symbol = "cloud.snow.fill"
    case 95: name = "thunderstorm"; symbol = "cloud.bolt.rain.fill"
    case 96: name = "thunderstorm_hail_slight"; symbol = "cloud.hail.fill"
    case 99: name = "thunderstorm_hail_heavy"; symbol = "cloud.hail.fill"
    default: name = "unknown"; symbol = "questionmark.circle"
    }
    localizationKey = "mikshat_weather_condition_" + name
    symbolName = symbol
  }
}

struct MikshatWeatherWind {
  let localizationKey: String
  let bearingDegrees: Double?

  init(speedKmh: Double?, directionDegrees: Double?) {
    guard let speed = speedKmh, speed.isFinite, speed >= 0 else {
      localizationKey = "mikshat_weather_wind_unavailable"; bearingDegrees = nil; return
    }
    guard speed >= 0.5 else {
      localizationKey = "mikshat_weather_wind_calm"; bearingDegrees = nil; return
    }
    guard let direction = directionDegrees, direction.isFinite else {
      localizationKey = "mikshat_weather_wind_unavailable"; bearingDegrees = nil; return
    }
    let degrees = Self.normalize(direction)
    let directions = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
    localizationKey = "mikshat_weather_wind_" + directions[Int((degrees + 22.5) / 45) % 8]
    bearingDegrees = degrees
  }

  static func normalize(_ degrees: Double) -> Double {
    (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
  }
}
