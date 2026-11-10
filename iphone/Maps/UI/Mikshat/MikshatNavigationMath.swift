import Foundation

enum MikshatNavigationMath {
  enum CoordinateError: Error { case invalid }

  static func normalize(_ degrees: Double) -> Double {
    (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
  }

  static func relativeBearing(bearing: Double, heading: Double) -> Double {
    normalize(bearing - heading)
  }

  static func bearing(latitude: Double, longitude: Double,
                      targetLatitude: Double = 21.422487, targetLongitude: Double = 39.826206) -> Double {
    let a = latitude * .pi / 180
    let b = targetLatitude * .pi / 180
    let delta = (targetLongitude - longitude) * .pi / 180
    return normalize(atan2(sin(delta) * cos(b), cos(a) * sin(b) - sin(a) * cos(b) * cos(delta)) * 180 / .pi)
  }

  static func ascii(_ text: String) -> String {
    text.reduce(into: "") { result, character in
      if let digit = character.wholeNumberValue, (0...9).contains(digit) {
        result += String(digit)
      } else if character == "." || character == "٫" || character == "," {
        result += "."
      } else if !character.isWhitespace {
        result.append(character)
      }
    }
  }

  static func minuteInput(_ text: String) -> String {
    let normalized = ascii(text)
    let digits = normalized.replacingOccurrences(of: ".", with: "")
    guard digits.allSatisfy({ $0.isNumber }) else { return normalized }
    let limited = String(digits.prefix(5))
    guard limited.count >= 2 else { return limited }
    let split = limited.index(limited.startIndex, offsetBy: 2)
    return String(limited[..<split]) + "." + String(limited[split...])
  }

  static func coordinate(degrees: String, minutes: String, latitude: Bool, negative: Bool = false) throws -> Double {
    let d = ascii(degrees)
    let m = ascii(minutes)
    let degreePattern = latitude ? "^[0-9]{1,2}$" : "^[0-9]{1,3}$"
    guard d.range(of: degreePattern, options: .regularExpression) != nil,
          m.range(of: "^[0-9]{2}\\.[0-9]{0,3}$", options: .regularExpression) != nil,
          let degreesValue = Double(d), let minutesValue = Double(m),
          degreesValue <= (latitude ? 90 : 180), minutesValue < 60,
          degreesValue < (latitude ? 90 : 180) || minutesValue == 0 else {
      throw CoordinateError.invalid
    }
    return (degreesValue + minutesValue / 60) * (negative ? -1 : 1)
  }

  static func ddm(_ value: Double, latitude: Bool) -> String {
    let total = Int((abs(value) * 60_000).rounded())
    let direction = latitude ? (value < 0 ? "S" : "N") : (value < 0 ? "W" : "E")
    // Assemble the rounded integer components so locale formatting cannot remove zero padding.
    func padded(_ number: Int, width: Int) -> String {
      let digits = String(number)
      return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
    let degrees = padded(total / 60_000, width: latitude ? 2 : 3)
    let minutes = padded((total % 60_000) / 1000, width: 2)
    let fraction = padded(total % 1000, width: 3)
    return "\(direction) \(degrees)° \(minutes).\(fraction)′"
  }

  // 0: phone sensor, 1: GPS course, 2: GPS at 10 km/h or faster.
  static func usesGPS(mode: Int, speed: Double) -> Bool {
    mode == 1 || (mode == 2 && speed.isFinite && speed >= 10 / 3.6)
  }
}

struct MikshatTravelEstimate {
  private var samples: [(time: Double, speed: Double)] = []
  private var lastTime: Double?

  mutating func update(distance: Double, speed: Double, timestamp: Double, now: Double) -> Double? {
    guard distance.isFinite, distance >= 0, speed.isFinite, speed >= 0,
          abs(now - timestamp) <= 15 else { samples.removeAll(); return nil }
    if distance <= 10 { return 0 }
    guard speed >= 0.5 else { samples.removeAll(); return nil }
    if lastTime != timestamp {
      samples.append((timestamp, speed))
      lastTime = timestamp
    }
    samples.removeAll { now - $0.time > 30 }
    guard !samples.isEmpty else { return nil }
    let average = samples.reduce(0) { $0 + $1.speed } / Double(samples.count)
    return distance / average
  }
}

extension MikshatNavigationMath {
  static func dms(_ value: Double, latitude: Bool) -> String {
    let total = Int((abs(value) * 360_000).rounded())
    func pad(_ n: Int, _ width: Int) -> String {
      let digits = String(n)
      return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
    let direction = latitude ? (value < 0 ? "S" : "N") : (value < 0 ? "W" : "E")
    return "\(direction) \(pad(total / 360_000, latitude ? 2 : 3))° \(pad(total / 6000 % 60, 2))′ \(pad(total / 100 % 60, 2)).\(pad(total % 100, 2))″"
  }
  static func coordinatePairs(latitude: Double, longitude: Double) -> [String] {
    [String(format: "%.6f\n%.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude),
     ddm(latitude, latitude: true) + "\n" + ddm(longitude, latitude: false),
     dms(latitude, latitude: true) + "\n" + dms(longitude, latitude: false)]
  }
}


extension MikshatNavigationMath {
  static func parseDecimalPair(_ text: String) -> (latitude: Double, longitude: Double)? {
    // Preserve whitespace between decimal latitude and longitude while normalizing Arabic digits.
    let normalized = text.map { character -> String in
      if character.isWhitespace { return " " }
      if character == "," || character == "،" { return "," }
      return ascii(String(character))
    }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "() "))
    let pattern = "^([+-]?[0-9]{1,2}(?:\\.[0-9]+)?)[,، ]+([+-]?[0-9]{1,3}(?:\\.[0-9]+)?)$"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
          let latRange = Range(match.range(at: 1), in: normalized),
          let lonRange = Range(match.range(at: 2), in: normalized),
          let latitude = Double(normalized[latRange]), let longitude = Double(normalized[lonRange]),
          abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
    return (latitude, longitude)
  }
}


extension MikshatNavigationMath {
  static func distanceParts(_ formatted: String) -> (value: String, unit: String) {
    guard let range = formatted.range(of: "[\\p{N}]+(?:[.,٫٬][\\p{N}]+)*", options: .regularExpression) else { return (formatted, "") }
    return (String(formatted[range]), formatted.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespacesAndNewlines))
  }
}


extension MikshatNavigationMath {
  static func shareLink(latitude: Double, longitude: Double, name: String) -> URL? {
    guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
    var components = URLComponents(string: "https://mukshatapp.github.io/map/")!
    let pair = String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    components.queryItems = [URLQueryItem(name: "ll", value: pair)]
    if !name.isEmpty { components.queryItems?.append(URLQueryItem(name: "n", value: name)) }
    return components.url
  }

  static func mikshatMapLink(_ url: URL) -> URL? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
          components.host?.lowercased() == "mukshatapp.github.io",
          ["/map", "/map/"].contains(components.path),
          components.queryItems?.filter({ $0.name == "ll" }).count == 1,
          let pair = components.queryItems?.first(where: { $0.name == "ll" })?.value,
          parseDecimalPair(pair) != nil else { return nil }
    var target = URLComponents(string: "om://map")!
    target.queryItems = components.queryItems
    return target.url
  }
}


extension MikshatNavigationMath {
  static func normalizedIncomingLink(_ url: URL) -> URL? {
    if url.scheme?.lowercased() == "mikshat-maps" {
      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.host?.lowercased() == "map",
            components.queryItems?.filter({ $0.name == "ll" }).count == 1,
            let pair = components.queryItems?.first(where: { $0.name == "ll" })?.value,
            parseDecimalPair(pair) != nil else { return nil }
      components.scheme = "om"
      return components.url
    }
    return url
  }
}


extension MikshatNavigationMath {
  static func sensorHeading(trueHeading: Double, magneticHeading: Double, accuracy: Double, age: Double, activeSensor: Bool = false) -> Double? {
    // A live heading service can legitimately retain the same reading while
    // stationary; it clears that reading on pause, shutdown or sensor error.
    guard accuracy.isFinite, (0...45).contains(accuracy), age.isFinite, age <= 15,
          activeSensor || abs(age) <= 15 else { return nil }
    if trueHeading.isFinite, (0..<360).contains(trueHeading) { return trueHeading }
    if magneticHeading.isFinite, (0..<360).contains(magneticHeading) { return magneticHeading }
    return nil
  }

  static func courseHeading(course: Double, speed: Double, accuracy: Double, age: Double) -> Double? {
    guard course.isFinite, (0..<360).contains(course), speed.isFinite, speed >= 0.5,
          accuracy.isFinite, accuracy < 0 || accuracy <= 45, age.isFinite, abs(age) <= 15 else { return nil }
    return course
  }

  static func selectHeading(mode: Int, speed: Double, sensor: Double?, course: Double?) -> (degrees: Double?, gps: Bool) {
    if mode == 1 { return (course, true) }
    if usesGPS(mode: mode, speed: speed), let course { return (course, true) }
    return (sensor, false)
  }
}
