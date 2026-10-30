import Foundation

enum MikshatNavigationMath {
  enum CoordinateError: Error { case invalid }

  static func normalize(_ degrees: Double) -> Double {
    (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
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
    let average = samples.map(\.speed).reduce(0, +) / Double(samples.count)
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
    [String(format: "%.6f, %.6f", latitude, longitude),
     ddm(latitude, latitude: true) + "\n" + ddm(longitude, latitude: false),
     dms(latitude, latitude: true) + "\n" + dms(longitude, latitude: false)]
  }
}
