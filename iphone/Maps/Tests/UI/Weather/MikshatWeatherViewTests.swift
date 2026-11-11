@testable import Organic_Maps__Debug_
import XCTest
import UIKit

final class MikshatWeatherViewTests: XCTestCase {
  @MainActor
  func testSelectedMapPointAndFallbackNameAreRenderedBeforeAnyRequest() throws {
    let weather = MikshatWeatherViewController(name: "  ", latitude: 24.65001, longitude: 46.71002)
    weather.loadViewIfNeeded()
    weather.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
    weather.view.layoutIfNeeded()
    XCTAssertEqual(try label("weather.location", in: weather.view).text, L("mikshat_weather_selected_location"))
    XCTAssertEqual(try label("weather.coordinates", in: weather.view).text, "24.65001, 46.71002")
    XCTAssertEqual(try label("weather.title", in: weather.view).text, L("mikshat_weather_title"))
    XCTAssertFalse(descendants(weather.view).contains { $0.accessibilityIdentifier == "weather.current" })
    XCTAssertGreaterThanOrEqual(try element("weather.close", in: weather.view).bounds.width, 44)
  }

  @MainActor
  func testInvalidMapCoordinatesCannotTriggerRefresh() throws {
    let weather = MikshatWeatherViewController(name: "اختبار الموقع", latitude: 91, longitude: 46)
    weather.loadViewIfNeeded()
    let refresh = try XCTUnwrap(try element("weather.refresh", in: weather.view) as? UIButton)
    XCTAssertFalse(refresh.isEnabled)
    XCTAssertEqual(try label("weather.status", in: weather.view).text, L("mikshat_weather_invalid_location"))
  }

  @MainActor
  func testFixtureForecastSupportsRTLAppearanceAndNativeScreenshots() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = MikshatWeatherRepository(cacheDirectory: directory, client: WeatherFixtureClient())
    let cases: [(String, CGSize, UIUserInterfaceStyle)] = [
      ("light-portrait", CGSize(width: 390, height: 844), .light),
      ("dark-portrait", CGSize(width: 390, height: 844), .dark),
      ("light-landscape", CGSize(width: 844, height: 390), .light),
      ("dark-landscape", CGSize(width: 844, height: 390), .dark),
    ]
    for (name, size, style) in cases {
      let weather = MikshatWeatherViewController(name: "روضة التنهات", latitude: 24.65, longitude: 46.71,
                                                repository: repository)
      let (window, container) = host(weather, size: size, style: style)
      defer { window.isHidden = true }
      try await waitUntil("Fixture forecast rendered") {
        self.descendants(weather.view).contains { $0.accessibilityIdentifier == "weather.current" }
          && (try? self.element("weather.refresh", in: weather.view) as? UIButton)?.isEnabled == true
      }
      layout(container)
      let hours = try XCTUnwrap(try element("weather.hours", in: weather.view) as? UIScrollView)
      let cards = try XCTUnwrap(hours.subviews.compactMap { $0 as? UIStackView }.first).arrangedSubviews
      XCTAssertEqual(cards.count, 12)
      XCTAssertEqual(hours.semanticContentAttribute, .forceRightToLeft)
      XCTAssertGreaterThan(try XCTUnwrap(cards.first).frame.minX, try XCTUnwrap(cards.last).frame.minX)
      XCTAssertEqual(hours.contentOffset.x, max(0, hours.contentSize.width - hours.bounds.width), accuracy: 1)
      XCTAssertGreaterThan(hours.bounds.height, 100)
      XCTAssertFalse(hours.hasAmbiguousLayout)
      XCTAssertTrue(cards.allSatisfy { $0.isAccessibilityElement && !($0.accessibilityLabel ?? "").isEmpty })
      let temperature = try label("weather.current.temperature", in: weather.view)
      XCTAssertEqual((temperature.text ?? "").components(separatedBy: "°C").count - 1, 1)
      let icon = try XCTUnwrap(try element("weather.current.icon", in: weather.view) as? UIImageView)
      let dayIcon = try XCTUnwrap(icon.image)
      weather.overrideUserInterfaceStyle = style == .light ? .dark : .light
      layout(container)
      XCTAssertEqual(icon.image, dayIcon, "Changing app appearance must not change the forecast's day/night icon")
      weather.overrideUserInterfaceStyle = .unspecified
      layout(container)
      try writeScreenshot(container.view, name: name)
      let page = try XCTUnwrap(descendants(weather.view).compactMap { $0 as? UIScrollView }.first { $0 !== hours })
      page.setContentOffset(CGPoint(x: 0, y: max(0, page.contentSize.height - page.bounds.height)), animated: false)
      layout(container)
      try writeScreenshot(container.view, name: name + "-forecast")

      // Keep the same visible hour and fraction when data rebuilds and the viewport resizes.
      hours.setContentOffset(CGPoint(x: hours.contentSize.width - hours.bounds.width - 300, y: 0), animated: false)
      layout(container)
      let right = hours.contentOffset.x + hours.bounds.width
      let anchor = try XCTUnwrap(cards.first { $0.frame.minX < right && $0.frame.maxX > hours.contentOffset.x })
      let identifier = try XCTUnwrap(anchor.accessibilityIdentifier)
      let fraction = (anchor.frame.maxX - right) / anchor.frame.width
      let refresh = try XCTUnwrap(try element("weather.refresh", in: weather.view) as? UIButton)
      refresh.sendActions(for: .touchUpInside)
      try await waitUntil("Refreshed forecast completed") { refresh.isEnabled }
      layout(container)
      try assertHourlyAnchor(identifier, fraction: fraction, in: hours)
      window.frame = CGRect(origin: .zero, size: CGSize(width: size.height, height: size.width))
      container.view.frame = window.bounds
      layout(container)
      try assertHourlyAnchor(identifier, fraction: fraction, in: hours)

      // Returning to the first hour keeps it pinned after resizing back.
      hours.setContentOffset(CGPoint(x: hours.contentSize.width - hours.bounds.width, y: 0), animated: false)
      window.frame = CGRect(origin: .zero, size: size)
      container.view.frame = window.bounds
      layout(container)
      XCTAssertEqual(hours.contentOffset.x, max(0, hours.contentSize.width - hours.bounds.width), accuracy: 1)
      window.isHidden = true
    }
  }

  @MainActor
  func testLargeDynamicTypeRemainsScrollableOnSmallPhone() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = MikshatWeatherRepository(cacheDirectory: directory, client: WeatherFixtureClient())
    let weather = MikshatWeatherViewController(name: "الموقع المحدد على الخريطة", latitude: 24.65, longitude: 46.71,
                                              repository: repository)
    let (window, container) = host(weather, size: CGSize(width: 320, height: 568),
                                   category: .accessibilityExtraExtraExtraLarge)
    defer { window.isHidden = true }
    try await waitUntil("Large type forecast rendered") {
      self.descendants(weather.view).contains { $0.accessibilityIdentifier == "weather.current" }
    }
    layout(container)
    let page = try XCTUnwrap(descendants(weather.view).compactMap { $0 as? UIScrollView }
      .first { $0.accessibilityIdentifier != "weather.hours" })
    XCTAssertGreaterThan(page.contentSize.height, page.bounds.height)
    XCTAssertFalse(weather.view.hasAmbiguousLayout)
    XCTAssertFalse(try element("weather.current", in: weather.view).hasAmbiguousLayout)
    XCTAssertEqual(weather.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
    XCTAssertGreaterThanOrEqual(try element("weather.close", in: weather.view).bounds.height, 44)
    try writeScreenshot(container.view, name: "large-type-small-phone")
    page.setContentOffset(CGPoint(x: 0, y: max(0, page.contentSize.height - page.bounds.height)), animated: false)
    layout(container)
    try writeScreenshot(container.view, name: "large-type-small-phone-forecast")
  }

  @MainActor
  func testFailedRefreshKeepsSelectedSiteCacheAndAnotherSiteHasNoSavedForecast() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinate = MikshatWeatherCoordinate(latitude: 24.65, longitude: 46.71)
    let seed = MikshatWeatherRepository(cacheDirectory: directory, client: WeatherFixtureClient())
    _ = try await seed.refresh(for: coordinate)
    let offline = WeatherFixtureClient(fails: true)
    let repository = MikshatWeatherRepository(cacheDirectory: directory, client: offline)
    let weather = MikshatWeatherViewController(name: "الموقع المحفوظ", latitude: 24.65, longitude: 46.71,
                                              repository: repository)
    let (window, container) = host(weather, size: CGSize(width: 390, height: 844))
    defer { window.isHidden = true }
    try await waitUntil("Saved forecast rendered") {
      self.descendants(weather.view).contains { $0.accessibilityIdentifier == "weather.current" }
        && (try? self.element("weather.refresh", in: weather.view) as? UIButton)?.isEnabled == true
    }
    let refresh = try XCTUnwrap(try element("weather.refresh", in: weather.view) as? UIButton)
    refresh.sendActions(for: .touchUpInside)
    try await waitUntil("Failed refresh completed") { refresh.isEnabled }
    let calls = await offline.calls
    XCTAssertGreaterThan(calls, 0)
    XCTAssertFalse(try element("weather.saved", in: weather.view).isHidden)
    XCTAssertFalse(try element("weather.current", in: weather.view).isHidden)
    XCTAssertNotNil(try label("weather.updated", in: weather.view).text)
    layout(container)
    try writeScreenshot(container.view, name: "saved-after-failed-refresh")
    window.isHidden = true

    let other = MikshatWeatherViewController(name: "موقع آخر", latitude: 30, longitude: 40, repository: repository)
    let (otherWindow, otherContainer) = host(other, size: CGSize(width: 390, height: 844))
    defer { otherWindow.isHidden = true }
    try await waitUntil("Missing saved site reported") {
      (try? self.label("weather.status", in: other.view).text)?.hasPrefix(L("mikshat_weather_no_saved_forecast")) == true
    }
    XCTAssertFalse(descendants(other.view).contains { $0.accessibilityIdentifier == "weather.current" })
    XCTAssertEqual(try label("weather.location", in: other.view).text, "موقع آخر")
    layout(otherContainer)
    try writeScreenshot(otherContainer.view, name: "no-saved-selected-site")
  }

  @MainActor
  func testCloseIgnoresLateForecastResult() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = WeatherFixtureClient(delayNanoseconds: 500_000_000)
    let repository = MikshatWeatherRepository(cacheDirectory: directory, client: client)
    let weather = MikshatWeatherViewController(name: "تحميل مؤجل", latitude: 24.65, longitude: 46.71,
                                              repository: repository)
    let (window, _) = host(weather, size: CGSize(width: 390, height: 844))
    defer { window.isHidden = true }
    for _ in 0..<100 {
      if await client.calls > 0 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let calls = await client.calls
    XCTAssertGreaterThan(calls, 0)
    let close = try XCTUnwrap(try element("weather.close", in: weather.view) as? UIButton)
    close.sendActions(for: .touchUpInside)
    try await Task.sleep(nanoseconds: 650_000_000)
    XCTAssertFalse(descendants(weather.view).contains { $0.accessibilityIdentifier == "weather.current" })
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("MikshatWeatherUI-" + UUID().uuidString,
                                                                isDirectory: true)
  }

  @MainActor
  private func element(_ identifier: String, in root: UIView,
                       file: StaticString = #filePath, line: UInt = #line) throws -> UIView {
    try XCTUnwrap(descendants(root).first { $0.accessibilityIdentifier == identifier }, file: file, line: line)
  }

  @MainActor
  private func label(_ identifier: String, in root: UIView,
                     file: StaticString = #filePath, line: UInt = #line) throws -> UILabel {
    try XCTUnwrap(try element(identifier, in: root, file: file, line: line) as? UILabel, file: file, line: line)
  }

  @MainActor
  private func descendants(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap { descendants($0) } }

  @MainActor
  private func assertHourlyAnchor(_ identifier: String, fraction: CGFloat, in hours: UIScrollView,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
    let card = try element(identifier, in: hours, file: file, line: line)
    let rect = card.convert(card.bounds, to: hours)
    XCTAssertEqual((rect.maxX - hours.contentOffset.x - hours.bounds.width) / rect.width, fraction,
                   accuracy: 0.01, file: file, line: line)
  }

  @MainActor
  private func layout(_ container: UIViewController) {
    for _ in 0..<3 { container.view.layoutIfNeeded(); container.children.forEach { $0.view.layoutIfNeeded() } }
  }

  @MainActor
  private func waitUntil(_ description: String, condition: () -> Bool) async throws {
    for _ in 0..<150 {
      if condition() { return }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail(description)
    throw URLError(.timedOut)
  }

  @MainActor
  private func host(_ weather: MikshatWeatherViewController, size: CGSize,
                    style: UIUserInterfaceStyle = .light,
                    category: UIContentSizeCategory = .large) -> (UIWindow, UIViewController) {
    // Use the existing phone scene so UIKit delivers appearance callbacks in a scene-based app.
    // The separate, non-key test window leaves the application's window and root controller untouched.
    let foregroundScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter {
      $0.session.role == .windowApplication &&
        ($0.activationState == .foregroundActive || $0.activationState == .foregroundInactive)
    }
    let scene = foregroundScenes.first { $0.activationState == .foregroundActive } ?? foregroundScenes.first
    let frame = CGRect(origin: .zero, size: size)
    let window: UIWindow
    if let scene {
      window = UIWindow(windowScene: scene)
      window.frame = frame
    } else {
      window = UIWindow(frame: frame)
    }
    window.overrideUserInterfaceStyle = style
    let container = UIViewController()
    container.loadViewIfNeeded()
    container.view.frame = window.bounds
    container.view.semanticContentAttribute = .forceRightToLeft
    container.addChild(weather)
    weather.view.frame = container.view.bounds
    weather.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    weather.view.semanticContentAttribute = .forceRightToLeft
    container.view.addSubview(weather.view)
    weather.didMove(toParent: container)
    container.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
      UITraitCollection(preferredContentSizeCategory: category), UITraitCollection(userInterfaceStyle: style),
      UITraitCollection(layoutDirection: .rightToLeft),
    ]), forChild: weather)
    window.rootViewController = container
    window.isHidden = false
    layout(container)
    return (window, container)
  }

  @MainActor
  private func writeScreenshot(_ view: UIView, name: String) throws {
    view.layoutIfNeeded()
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { view.layer.render(in: $0.cgContext) }
    let directory = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent("weather-\(name)-fixture.png"), options: .atomic)
    let attachment = XCTAttachment(image: image)
    attachment.name = "weather-\(name)-fixture"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

private actor WeatherFixtureClient: MikshatWeatherClient {
  private(set) var calls = 0
  let fails: Bool
  let delayNanoseconds: UInt64
  init(fails: Bool = false, delayNanoseconds: UInt64 = 0) {
    self.fails = fails
    self.delayNanoseconds = delayNanoseconds
  }

  func fetch(for coordinate: MikshatWeatherCoordinate, now: Date) async throws -> MikshatWeatherSnapshot {
    calls += 1
    if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
    if fails { throw URLError(.notConnectedToInternet) }
    let firstHour = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 3600) + 1) * 3600)
    let codes = [0, 1, 2, 3, 45, 51, 61, 66, 71, 80, 85, 95]
    let hourly = (0..<12).map { index in
      MikshatWeatherSample(time: firstHour.addingTimeInterval(Double(index) * 3600), temperatureC: 26,
                           windSpeedKmh: 16, windDirectionDegrees: Double(index * 30), windGustsKmh: 25,
                           weatherCode: codes[index], isDay: index < 6)
    }
    let current = MikshatWeatherSample(time: now.addingTimeInterval(-300), temperatureC: 27, windSpeedKmh: 18,
                                       windDirectionDegrees: 45, windGustsKmh: 31, weatherCode: 0, isDay: true)
    return MikshatWeatherSnapshot(coordinate: coordinate, fetchedAt: now, timeZoneIdentifier: "Asia/Riyadh",
                                  current: current, hourly: hourly)
  }
}
