@testable import Organic_Maps__Debug_
import XCTest
import UIKit

final class MikshatWeatherViewTests: XCTestCase {
  private var isRTL: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("ar") == true }

  @MainActor
  func testSelectedMapPointAndFallbackNameAreRenderedBeforeAnyRequest() throws {
    let weather = MikshatWeatherViewController(name: "  ", latitude: 24.65001, longitude: 46.71002)
    weather.loadViewIfNeeded()
    weather.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
    weather.view.layoutIfNeeded()
    XCTAssertEqual(try label("weather.location", in: weather.view).text, L("mikshat_weather_selected_location"))
    XCTAssertEqual(try label("weather.coordinates", in: weather.view).text, "24.65001, 46.71002")
    XCTAssertEqual(try label("weather.title", in: weather.view).text, L("mikshat_weather_title"))
    XCTAssertEqual(weather.view.effectiveUserInterfaceLayoutDirection, isRTL ? .rightToLeft : .leftToRight)
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
      ("compact-phone-portrait", CGSize(width: 320, height: 568), .light),
      ("compact-phone-landscape", CGSize(width: 568, height: 320), .light),
      ("light-portrait", CGSize(width: 390, height: 844), .light),
      ("dark-portrait", CGSize(width: 390, height: 844), .dark),
      ("light-landscape", CGSize(width: 844, height: 390), .light),
      ("dark-landscape", CGSize(width: 844, height: 390), .dark),
      ("large-phone-portrait", CGSize(width: 430, height: 932), .light),
      ("ipad-portrait", CGSize(width: 768, height: 1024), .light),
      ("ipad-landscape", CGSize(width: 1024, height: 768), .dark),
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
      try assertNormalForecastFits(in: weather.view, context: name)
      try assertSheetPolicy(weather, size: size, context: name)
      let hours = try XCTUnwrap(try element("weather.hours", in: weather.view) as? UIScrollView)
      let cards = try XCTUnwrap(hours.subviews.compactMap { $0 as? UIStackView }.first).arrangedSubviews
      try assertHorizontalHours(in: hours, context: name)
      XCTAssertEqual(hours.contentOffset.x, isRTL ? max(0, hours.contentSize.width - hours.bounds.width) : 0, accuracy: 1)
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
      let page = try XCTUnwrap(try element("weather.scroll", in: weather.view) as? UIScrollView)
      page.setContentOffset(CGPoint(x: 0, y: max(0, page.contentSize.height - page.bounds.height)), animated: false)
      layout(container)
      try writeScreenshot(container.view, name: name + "-forecast")
      hours.setContentOffset(CGPoint(x: isRTL ? 0 : max(0, hours.contentSize.width - hours.bounds.width), y: 0), animated: false)
      layout(container)
      try assertVisible(try XCTUnwrap(cards.last), in: hours, context: name + "-twelfth-hour")

      // Keep the same visible hour and fraction when data rebuilds and the viewport resizes.
      hours.setContentOffset(CGPoint(x: isRTL ? hours.contentSize.width - hours.bounds.width - 300 : 300, y: 0), animated: false)
      layout(container)
      let right = hours.contentOffset.x + hours.bounds.width
      let anchor = try XCTUnwrap(cards.first { $0.frame.minX < right && $0.frame.maxX > hours.contentOffset.x })
      let identifier = try XCTUnwrap(anchor.accessibilityIdentifier)
      let fraction = isRTL ? (anchor.frame.maxX - right) / anchor.frame.width
        : (hours.contentOffset.x - anchor.frame.minX) / anchor.frame.width
      let refresh = try XCTUnwrap(try element("weather.refresh", in: weather.view) as? UIButton)
      refresh.sendActions(for: .touchUpInside)
      try await waitUntil("Refreshed forecast completed") { refresh.isEnabled }
      layout(container)
      try assertHourlyAnchor(identifier, fraction: fraction, in: hours)
      resize(window: window, container: container, size: CGSize(width: size.height, height: size.width))
      try assertHourlyAnchor(identifier, fraction: fraction, in: hours)
      try assertNormalForecastFits(in: weather.view, context: name + "-rotated")
      try assertSheetPolicy(weather, size: CGSize(width: size.height, height: size.width), context: name + "-rotated")
      try assertHorizontalHours(in: hours, context: name + "-rotated")
      try writeScreenshot(container.view, name: name + "-rotated")

      // Returning to the first hour keeps it pinned after resizing back.
      hours.setContentOffset(CGPoint(x: isRTL ? hours.contentSize.width - hours.bounds.width : 0, y: 0), animated: false)
      resize(window: window, container: container, size: size)
      XCTAssertEqual(hours.contentOffset.x, isRTL ? max(0, hours.contentSize.width - hours.bounds.width) : 0, accuracy: 1)
      try assertSheetPolicy(weather, size: size, context: name + "-returned")
      window.isHidden = true
    }
  }

  @MainActor
  func testLargeDynamicTypeRemainsScrollableOnSmallPhone() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = MikshatWeatherRepository(cacheDirectory: directory, client: WeatherFixtureClient())
    let cases: [(String, CGSize)] = [
      ("small-phone", CGSize(width: 320, height: 568)),
      ("large-phone", CGSize(width: 430, height: 932)),
      ("ipad", CGSize(width: 768, height: 1024)),
    ]
    for (name, size) in cases {
      let weather = MikshatWeatherViewController(name: "الموقع المحدد على الخريطة", latitude: 24.65, longitude: 46.71,
                                                repository: repository)
      let (window, container) = host(weather, size: size, category: .accessibilityExtraExtraExtraLarge)
      defer { window.isHidden = true }
      try await waitUntil("Large type forecast rendered") {
        self.descendants(weather.view).contains { $0.accessibilityIdentifier == "weather.current" }
      }
      for (orientation, viewport) in [("portrait", size), ("landscape", CGSize(width: size.height, height: size.width))] {
        resize(window: window, container: container, size: viewport)
        let page = try XCTUnwrap(try element("weather.scroll", in: weather.view) as? UIScrollView)
        if name == "small-phone" { XCTAssertGreaterThan(page.contentSize.height, page.bounds.height) }
        XCTAssertTrue(page.isScrollEnabled)
        XCTAssertFalse(weather.view.hasAmbiguousLayout)
        XCTAssertFalse(try element("weather.current", in: weather.view).hasAmbiguousLayout)
        XCTAssertEqual(weather.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
        let close = try element("weather.close", in: weather.view)
        XCTAssertGreaterThanOrEqual(close.bounds.height, 44)
        try assertVisible(close, in: weather.view)
        page.setContentOffset(CGPoint(x: 0, y: -page.adjustedContentInset.top), animated: false)
        layout(container)
        try writeScreenshot(container.view, name: "large-type-\(name)-\(orientation)")
        let hours = try XCTUnwrap(try element("weather.hours", in: weather.view) as? UIScrollView)
        try assertHorizontalHours(in: hours, context: "large-type-\(name)-\(orientation)")
        let refresh = try element("weather.refresh", in: weather.view)
        page.scrollRectToVisible(refresh.convert(refresh.bounds, to: page), animated: false)
        layout(container)
        try assertVisible(refresh, in: weather.view)
        let attribution = try element("weather.attribution", in: weather.view)
        page.scrollRectToVisible(attribution.convert(attribution.bounds, to: page), animated: false)
        layout(container)
        try assertVisible(attribution, in: weather.view)
        try writeScreenshot(container.view, name: "large-type-\(name)-\(orientation)-forecast")
      }
      window.isHidden = true
    }
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
  private func assertSheetPolicy(_ weather: MikshatWeatherViewController, size: CGSize, context: String,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
    let sheet = try XCTUnwrap(weather.sheetPresentationController, file: file, line: line)
    XCTAssertEqual(sheet.detents.count, 1, file: file, line: line)
    let phonePortrait = min(size.width, size.height) < 600 && size.height >= size.width
    XCTAssertEqual(sheet.selectedDetentIdentifier?.rawValue,
                   phonePortrait ? "mikshat.weather.content" : UISheetPresentationController.Detent.Identifier.large.rawValue,
                   "Sheet policy must follow the device and window orientation: \(context)", file: file, line: line)
    guard phonePortrait else { return }
    XCTAssertGreaterThan(weather.preferredContentSize.height, 0, file: file, line: line)
    if size.height >= 800 {
      XCTAssertLessThan(weather.preferredContentSize.height, size.height - 100,
                        "A normal portrait forecast must not leave a nearly full-height empty sheet: \(context)",
                        file: file, line: line)
    }
    let page = try element("weather.scroll", in: weather.view, file: file, line: line)
    let content = try element("weather.content", in: weather.view, file: file, line: line)
    XCTAssertEqual(content.convert(content.bounds, to: page).minY, 4, accuracy: 1,
                   "Content must start directly below the sheet header: \(context)", file: file, line: line)
    let hours = try XCTUnwrap(try element("weather.hours", in: weather.view, file: file, line: line) as? UIScrollView,
                             file: file, line: line)
    let stack = try XCTUnwrap(hours.subviews.compactMap { $0 as? UIStackView }.first, file: file, line: line)
    for card in stack.arrangedSubviews {
      let body = try XCTUnwrap(card.subviews.first, file: file, line: line)
      XCTAssertEqual(body.frame.minY, 11, accuracy: 1, "Hourly cards need portrait vertical breathing room: \(context)",
                     file: file, line: line)
      XCTAssertEqual(card.bounds.height - body.frame.maxY, 11, accuracy: 1, file: file, line: line)
    }
  }

  @MainActor
  private func assertNormalForecastFits(in root: UIView, context: String,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
    let page = try XCTUnwrap(try element("weather.scroll", in: root) as? UIScrollView, file: file, line: line)
    XCTAssertLessThanOrEqual(page.contentSize.height + page.adjustedContentInset.top + page.adjustedContentInset.bottom,
                             page.bounds.height + 1, "Normal forecast must fit without vertical scrolling: \(context)",
                             file: file, line: line)
    let identifiers = ["weather.title", "weather.close", "weather.location", "weather.coordinates", "weather.current",
                       "weather.current.condition", "weather.current.temperature", "weather.current.icon", "weather.updated",
                       "weather.hours", "weather.refresh", "weather.notice", "weather.attribution"]
    for identifier in identifiers {
      let view = try element(identifier, in: root, file: file, line: line)
      try assertVisible(view, in: root, context: context, file: file, line: line)
      if view.isDescendant(of: page) {
        try assertVisible(view, in: page, context: context, file: file, line: line)
      }
    }
    let title = try element("weather.title", in: root)
    let close = try element("weather.close", in: root)
    XCTAssertFalse(title.convert(title.bounds, to: root).intersects(close.convert(close.bounds, to: root)),
                   "Title and close action overlap: \(context)", file: file, line: line)
    let current = try element("weather.current", in: root)
    let hours = try element("weather.hours", in: root)
    XCTAssertFalse(current.convert(current.bounds, to: root).intersects(hours.convert(hours.bounds, to: root)),
                   "Current forecast and hourly strip overlap: \(context)", file: file, line: line)
    for label in descendants(current).compactMap({ $0 as? UILabel }) where !isHiddenInHierarchy(label, upTo: current) {
      try assertVisible(label, in: current, context: context, file: file, line: line)
    }
    XCTAssertGreaterThanOrEqual(try element("weather.refresh", in: root).bounds.height, 44, file: file, line: line)
    XCTAssertFalse(try element("weather.content", in: root).hasAmbiguousLayout, file: file, line: line)
  }

  @MainActor
  private func assertHorizontalHours(in hours: UIScrollView, context: String = "",
                                     file: StaticString = #filePath, line: UInt = #line) throws {
    let stack = try XCTUnwrap(hours.subviews.compactMap { $0 as? UIStackView }.first, file: file, line: line)
    let cards = stack.arrangedSubviews
    XCTAssertEqual(cards.count, 12, file: file, line: line)
    XCTAssertEqual(stack.axis, .horizontal, file: file, line: line)
    XCTAssertEqual(hours.semanticContentAttribute, isRTL ? .forceRightToLeft : .forceLeftToRight, file: file, line: line)
    XCTAssertEqual(stack.semanticContentAttribute, hours.semanticContentAttribute, file: file, line: line)
    XCTAssertGreaterThan(hours.contentSize.width, hours.bounds.width, file: file, line: line)
    XCTAssertLessThanOrEqual(hours.contentSize.height, hours.bounds.height + 1,
                             "Hourly forecast must scroll horizontally without a vertical clipping area", file: file, line: line)
    XCTAssertGreaterThan(hours.bounds.height, 0, file: file, line: line)
    XCTAssertFalse(hours.hasAmbiguousLayout, file: file, line: line)
    XCTAssertEqual(Set(cards.compactMap(\.accessibilityIdentifier)).count, 12, file: file, line: line)
    for (index, card) in cards.enumerated() {
      XCTAssertFalse(card.isHidden, file: file, line: line)
      XCTAssertFalse(card.hasAmbiguousLayout, file: file, line: line)
      XCTAssertTrue(card.isAccessibilityElement, file: file, line: line)
      XCTAssertFalse((card.accessibilityLabel ?? "").isEmpty, file: file, line: line)
      XCTAssertTrue((card.accessibilityIdentifier ?? "").hasPrefix("weather.hour."), file: file, line: line)
      XCTAssertGreaterThan(card.bounds.width, 0, file: file, line: line)
      XCTAssertGreaterThan(card.bounds.height, 0, file: file, line: line)
      let rect = card.convert(card.bounds, to: stack)
      XCTAssertGreaterThanOrEqual(rect.minY, -1, file: file, line: line)
      XCTAssertLessThanOrEqual(rect.maxY, stack.bounds.height + 1, file: file, line: line)
      for label in descendants(card).compactMap({ $0 as? UILabel }) where !isHiddenInHierarchy(label, upTo: card) {
        try assertVisible(label, in: card, context: context, file: file, line: line)
      }
      if index > 0 {
        let previous = cards[index - 1].convert(cards[index - 1].bounds, to: stack)
        if isRTL {
          XCTAssertLessThanOrEqual(rect.maxX, previous.minX + 1, "Future hours must follow right-to-left reading order",
                                   file: file, line: line)
        } else {
          XCTAssertGreaterThanOrEqual(rect.minX, previous.maxX - 1, "Future hours must follow left-to-right reading order",
                                      file: file, line: line)
        }
        XCTAssertEqual(rect.midY, previous.midY, accuracy: 1, file: file, line: line)
      }
    }
  }

  @MainActor
  private func assertVisible(_ view: UIView, in root: UIView, context: String = "",
                             file: StaticString = #filePath, line: UInt = #line) throws {
    let identifier: String
    if let label = view as? UILabel {
      let text = (label.text ?? label.attributedText?.string ?? "").replacingOccurrences(of: "\n", with: " ")
      identifier = "\(view.accessibilityIdentifier ?? root.accessibilityIdentifier ?? "UILabel") [\(text)]"
    } else {
      identifier = view.accessibilityIdentifier ?? String(describing: type(of: view))
    }
    XCTAssertFalse(isHiddenInHierarchy(view, upTo: root), "Hidden \(identifier): \(context)", file: file, line: line)
    let rect = view.convert(view.bounds, to: root)
    XCTAssertGreaterThan(rect.width, 0, "Zero width \(identifier): \(context)", file: file, line: line)
    XCTAssertGreaterThan(rect.height, 0, "Zero height \(identifier): \(context)", file: file, line: line)
    XCTAssertTrue(root.bounds.insetBy(dx: -1, dy: -1).contains(rect),
                  "Clipped \(identifier) \(rect) outside \(root.bounds): \(context)", file: file, line: line)
    if let label = view as? UILabel, !(label.text ?? label.attributedText?.string ?? "").isEmpty {
      if label.numberOfLines == 1 {
        let natural = label.textRect(forBounds: CGRect(x: 0, y: 0, width: 10_000, height: 10_000),
                                      limitedToNumberOfLines: 1)
        let permittedScale = label.adjustsFontSizeToFitWidth ? label.minimumScaleFactor : 1
        XCTAssertLessThanOrEqual(natural.width * permittedScale, label.bounds.width + 1,
                                 "Truncated single-line \(identifier): \(context)", file: file, line: line)
        XCTAssertLessThanOrEqual(natural.height * permittedScale, label.bounds.height + 1,
                                 "Clipped single-line \(identifier): \(context)", file: file, line: line)
      } else {
        let fullText = label.textRect(forBounds: CGRect(x: 0, y: 0, width: label.bounds.width, height: 10_000),
                                       limitedToNumberOfLines: 0)
        XCTAssertLessThanOrEqual(fullText.height, label.bounds.height + 1,
                                 "Clipped multiline \(identifier): \(context)", file: file, line: line)
      }
    } else if let text = view as? UITextView, !text.isScrollEnabled {
      XCTAssertLessThanOrEqual(text.sizeThatFits(CGSize(width: text.bounds.width, height: 10_000)).height,
                               text.bounds.height + 1, "Clipped text \(identifier): \(context)", file: file, line: line)
    }
  }

  @MainActor
  private func isHiddenInHierarchy(_ view: UIView, upTo root: UIView) -> Bool {
    var candidate: UIView? = view
    while let current = candidate {
      if current.isHidden || current.alpha < 0.01 { return true }
      if current === root { return false }
      candidate = current.superview
    }
    return true
  }

  @MainActor
  private func assertHourlyAnchor(_ identifier: String, fraction: CGFloat, in hours: UIScrollView,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
    let card = try element(identifier, in: hours, file: file, line: line)
    let rect = card.convert(card.bounds, to: hours)
    let actual = isRTL ? (rect.maxX - hours.contentOffset.x - hours.bounds.width) / rect.width
      : (hours.contentOffset.x - rect.minX) / rect.width
    XCTAssertEqual(actual, fraction,
                   accuracy: 0.01, file: file, line: line)
  }

  @MainActor
  private func layout(_ container: UIViewController) {
    for _ in 0..<4 {
      container.parent?.view.setNeedsLayout()
      container.view.setNeedsLayout()
      container.children.forEach { $0.view.setNeedsLayout() }
      container.parent?.view.layoutIfNeeded()
      container.view.layoutIfNeeded()
      container.children.forEach { $0.view.layoutIfNeeded() }
    }
    guard let weather = container.children.first else {
      XCTFail("The measured weather fixture must contain its production controller")
      return
    }
    let bounds = weather.view.bounds
    XCTAssertEqual(container.view.frame.minX, ResponsiveFixtureViewport.margin, accuracy: 1)
    XCTAssertEqual(container.view.frame.minY, ResponsiveFixtureViewport.margin, accuracy: 1)
    XCTAssertEqual(bounds.width, container.view.bounds.width, accuracy: 1)
    XCTAssertEqual(bounds.height, container.view.bounds.height, accuracy: 1)
    ResponsiveFixtureViewport.assertInsets(of: container.view, equalTo: .zero)
    ResponsiveFixtureViewport.assertInsets(of: weather.view,
                                           equalTo: ResponsiveFixtureViewport.insets(for: container.view.bounds.size))
  }

  @MainActor
  private func resize(window: UIWindow, container: UIViewController, size: CGSize) {
    window.frame = CGRect(origin: .zero, size: ResponsiveFixtureViewport.canvasSize(for: size))
    window.rootViewController?.view.frame = window.bounds
    container.view.frame = CGRect(origin: CGPoint(x: ResponsiveFixtureViewport.margin, y: ResponsiveFixtureViewport.margin),
                                  size: size)
    for weather in container.children {
      let category = weather.traitCollection.preferredContentSizeCategory
      container.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
        UITraitCollection(preferredContentSizeCategory: category),
        UITraitCollection(userInterfaceStyle: window.overrideUserInterfaceStyle),
        UITraitCollection(layoutDirection: isRTL ? .rightToLeft : .leftToRight),
        UITraitCollection(userInterfaceIdiom: min(size.width, size.height) >= 600 ? .pad : .phone),
        UITraitCollection(horizontalSizeClass: size.width >= 600 ? .regular : .compact),
        UITraitCollection(verticalSizeClass: size.height < 500 ? .compact : .regular),
      ]), forChild: weather)
      weather.additionalSafeAreaInsets = ResponsiveFixtureViewport.insets(for: size)
      weather.view.frame = container.view.bounds
    }
    layout(container)
    XCTAssertEqual(container.view.bounds.width, size.width, accuracy: 1, "Weather fixture viewport width")
    XCTAssertEqual(container.view.bounds.height, size.height, accuracy: 1, "Weather fixture viewport height")
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
    // Keep UIKit appearance callbacks while isolating each fixture from the scene's actual orientation.
    let foregroundScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter {
      $0.session.role == .windowApplication &&
        ($0.activationState == .foregroundActive || $0.activationState == .foregroundInactive)
    }
    let scene = foregroundScenes.first { $0.activationState == .foregroundActive } ?? foregroundScenes.first
    let frame = CGRect(origin: .zero, size: ResponsiveFixtureViewport.canvasSize(for: size))
    let window: UIWindow
    if let scene {
      window = UIWindow(windowScene: scene)
      window.frame = frame
    } else {
      window = UIWindow(frame: frame)
    }
    window.overrideUserInterfaceStyle = style
    let canvas = UIViewController()
    canvas.loadViewIfNeeded()
    canvas.view.frame = window.bounds
    let container = UIViewController()
    container.loadViewIfNeeded()
    container.view.autoresizingMask = []
    canvas.addChild(container)
    container.view.frame = CGRect(origin: CGPoint(x: ResponsiveFixtureViewport.margin, y: ResponsiveFixtureViewport.margin),
                                  size: size)
    canvas.view.addSubview(container.view)
    container.didMove(toParent: canvas)
    container.view.semanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
    container.addChild(weather)
    container.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
      UITraitCollection(preferredContentSizeCategory: category), UITraitCollection(userInterfaceStyle: style),
      UITraitCollection(layoutDirection: isRTL ? .rightToLeft : .leftToRight),
    ]), forChild: weather)
    weather.view.frame = container.view.bounds
    weather.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.view.addSubview(weather.view)
    weather.didMove(toParent: container)
    window.rootViewController = canvas
    window.isHidden = false
    resize(window: window, container: container, size: size)
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

actor WeatherFixtureClient: MikshatWeatherClient {
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
