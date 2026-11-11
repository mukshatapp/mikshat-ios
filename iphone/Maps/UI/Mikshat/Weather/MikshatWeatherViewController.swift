import UIKit
import Network

/// Weather for an immutable selected map point. This screen never requests the device location.
@MainActor
final class MikshatWeatherViewController: UIViewController {
  private let coordinate: MikshatWeatherCoordinate
  private let locationName: String
  private let repository: MikshatWeatherRepository
  private let scrollView = UIScrollView()
  private let content = UIStackView()
  private let statusStack = UIStackView()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let statusLabel = weatherLabel(style: .subheadline, secondary: true)
  private let currentCard = WeatherCard()
  private let currentStack = UIStackView()
  private let currentIcon = UIImageView()
  private let conditionLabel = weatherLabel(style: .title3)
  private let temperatureLabel = weatherLabel(style: .largeTitle)
  private let windStack = UIStackView()
  private let cacheLabel = weatherLabel(style: .caption1, secondary: true)
  private let updatedLabel = weatherLabel(style: .caption1, secondary: true)
  private let hourlySection = UIStackView()
  private let hourlyScroll = WeatherHoursScrollView()
  private let hourlyStack = UIStackView()
  private let hourlyAvailability = weatherLabel(style: .footnote, secondary: true)
  private let refreshButton = UIButton(type: .system)
  private let attribution = UITextView()
  private var snapshot: MikshatWeatherSnapshot?
  private var showingCache = false
  private var fetchFailed = false
  private var isLoading = false
  private var isVisible = false
  private var isOnline: Bool?
  private var requestID = UUID()
  private var connectivityID = UUID()
  private var requestTask: Task<Void, Never>?
  private var pathMonitor: NWPathMonitor?
  private var displayTimer: Timer?
  private var lastLayoutWidth: CGFloat = 0

  init(name: String?, latitude: Double, longitude: Double,
       repository: MikshatWeatherRepository = .shared) {
    coordinate = MikshatWeatherCoordinate(latitude: latitude, longitude: longitude)
    let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    locationName = trimmedName.isEmpty ? L("mikshat_weather_selected_location") : trimmedName
    self.repository = repository
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .pageSheet
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit {
    requestTask?.cancel()
    pathMonitor?.cancel()
    displayTimer?.invalidate()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = L("mikshat_weather_title")
    view.backgroundColor = WeatherPalette.background
    view.tintColor = WeatherPalette.accent
    buildLayout()
    setLoading(false)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    isVisible = true
    startMonitoringConnectivity()
    displayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.updateDisplayedForecast() }
    }
    loadForecast(force: false)
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stopVisibleWork()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let availableWidth = scrollView.bounds.width
    if abs(lastLayoutWidth - availableWidth) > 1 {
      lastLayoutWidth = availableWidth
      if let snapshot { rebuildHourly(snapshot) }
    }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
      updateDisplayedForecast()
      configureAttribution()
    }
    if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true {
      currentCard.updateBorder()
      for case let card as WeatherCard in hourlyStack.arrangedSubviews { card.updateBorder() }
      configureAttribution()
    }
  }

  private func buildLayout() {
    let titleLabel = weatherLabel(style: .title2)
    titleLabel.text = title
    titleLabel.accessibilityIdentifier = "weather.title"
    titleLabel.accessibilityTraits.insert(.header)
    let close = UIButton(type: .system)
    close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    close.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 26), forImageIn: .normal)
    close.accessibilityLabel = L("close")
    close.accessibilityIdentifier = "weather.close"
    close.addTarget(self, action: #selector(closeScreen), for: .touchUpInside)
    close.setContentHuggingPriority(.required, for: .horizontal)
    let header = UIStackView(arrangedSubviews: [titleLabel, close])
    header.alignment = .center
    header.spacing = 12
    header.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header)
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.alwaysBounceVertical = true
    scrollView.keyboardDismissMode = .onDrag
    view.addSubview(scrollView)
    content.axis = .vertical
    content.spacing = 18
    content.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(content)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
      header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      close.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
      close.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
      scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 10),
      content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 18),
      content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -18),
      content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
      content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36),
    ])
    let location = weatherLabel(style: .title3)
    location.text = locationName
    location.accessibilityIdentifier = "weather.location"
    location.accessibilityTraits.insert(.header)
    let coordinates = weatherLabel(style: .subheadline, secondary: true)
    coordinates.text = coordinateText
    coordinates.accessibilityIdentifier = "weather.coordinates"
    coordinates.semanticContentAttribute = .forceLeftToRight
    coordinates.accessibilityLabel = String(format: L("mikshat_weather_coordinates"), coordinateText)
    content.addArrangedSubview(verticalStack([location, coordinates], spacing: 6))
    statusStack.axis = .horizontal
    statusStack.alignment = .center
    statusStack.spacing = 10
    statusStack.addArrangedSubview(spinner)
    statusStack.addArrangedSubview(statusLabel)
    statusLabel.accessibilityTraits.insert(.updatesFrequently)
    statusLabel.accessibilityIdentifier = "weather.status"
    content.addArrangedSubview(statusStack)
    currentStack.axis = .vertical
    currentStack.alignment = .fill
    currentStack.spacing = 14
    let currentTitle = weatherLabel(style: .headline)
    currentTitle.text = L("mikshat_weather_current")
    currentTitle.accessibilityTraits.insert(.header)
    currentStack.addArrangedSubview(currentTitle)
    currentIcon.contentMode = .scaleAspectFit
    currentIcon.accessibilityIdentifier = "weather.current.icon"
    currentIcon.tintColor = WeatherPalette.accent
    currentIcon.isAccessibilityElement = false
    currentIcon.translatesAutoresizingMaskIntoConstraints = false
    let iconContainer = UIView()
    iconContainer.addSubview(currentIcon)
    NSLayoutConstraint.activate([
      currentIcon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
      currentIcon.topAnchor.constraint(equalTo: iconContainer.topAnchor),
      currentIcon.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
      currentIcon.widthAnchor.constraint(equalToConstant: 68),
      currentIcon.heightAnchor.constraint(equalToConstant: 64),
    ])
    currentStack.addArrangedSubview(iconContainer)
    conditionLabel.accessibilityIdentifier = "weather.current.condition"
    currentStack.addArrangedSubview(conditionLabel)
    temperatureLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: .systemFont(ofSize: 48, weight: .semibold))
    temperatureLabel.textColor = WeatherPalette.accent
    temperatureLabel.numberOfLines = 1
    temperatureLabel.adjustsFontSizeToFitWidth = true
    temperatureLabel.minimumScaleFactor = 0.65
    temperatureLabel.semanticContentAttribute = .forceLeftToRight
    temperatureLabel.accessibilityIdentifier = "weather.current.temperature"
    currentStack.addArrangedSubview(temperatureLabel)
    windStack.spacing = 12
    windStack.distribution = .fillEqually
    currentStack.addArrangedSubview(windStack)
    cacheLabel.font = .preferredFont(forTextStyle: .headline)
    cacheLabel.textColor = WeatherPalette.accent
    currentStack.addArrangedSubview(verticalStack([cacheLabel, updatedLabel], spacing: 4))
    currentCard.install(currentStack)
    currentCard.accessibilityIdentifier = "weather.current"
    cacheLabel.accessibilityIdentifier = "weather.saved"
    updatedLabel.accessibilityIdentifier = "weather.updated"
    currentCard.isHidden = true
    hourlySection.axis = .vertical
    hourlySection.spacing = 10
    let hourlyTitle = weatherLabel(style: .headline)
    hourlyTitle.text = L("mikshat_weather_next_12_hours")
    hourlyTitle.accessibilityTraits.insert(.header)
    hourlySection.addArrangedSubview(hourlyTitle)
    hourlyScroll.showsHorizontalScrollIndicator = true
    hourlyScroll.alwaysBounceHorizontal = true
    hourlyScroll.semanticContentAttribute = .forceRightToLeft
    hourlyScroll.accessibilityIdentifier = "weather.hours"
    hourlyStack.axis = .horizontal
    hourlyStack.alignment = .fill
    hourlyStack.spacing = 10
    hourlyStack.semanticContentAttribute = .forceRightToLeft
    hourlyStack.translatesAutoresizingMaskIntoConstraints = false
    hourlyScroll.cards = hourlyStack
    hourlyScroll.addSubview(hourlyStack)
    NSLayoutConstraint.activate([
      hourlyStack.topAnchor.constraint(equalTo: hourlyScroll.contentLayoutGuide.topAnchor, constant: 2),
      hourlyStack.bottomAnchor.constraint(equalTo: hourlyScroll.contentLayoutGuide.bottomAnchor, constant: -8),
      hourlyStack.leadingAnchor.constraint(equalTo: hourlyScroll.contentLayoutGuide.leadingAnchor),
      hourlyStack.trailingAnchor.constraint(equalTo: hourlyScroll.contentLayoutGuide.trailingAnchor),
      hourlyStack.heightAnchor.constraint(equalTo: hourlyScroll.frameLayoutGuide.heightAnchor, constant: -10),
    ])
    hourlySection.addArrangedSubview(hourlyScroll)
    hourlySection.addArrangedSubview(hourlyAvailability)
    hourlySection.isHidden = true
    var configuration = UIButton.Configuration.filled()
    configuration.title = L("mikshat_weather_refresh")
    configuration.image = UIImage(systemName: "arrow.clockwise")
    configuration.imagePadding = 10
    configuration.baseBackgroundColor = WeatherPalette.accent
    configuration.baseForegroundColor = WeatherPalette.buttonText
    configuration.cornerStyle = .large
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var result = attributes
      result.font = UIFont.preferredFont(forTextStyle: .headline)
      return result
    }
    refreshButton.configuration = configuration
    refreshButton.accessibilityIdentifier = "weather.refresh"
    refreshButton.titleLabel?.numberOfLines = 0
    refreshButton.titleLabel?.adjustsFontForContentSizeCategory = true
    refreshButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    refreshButton.addTarget(self, action: #selector(refreshForecast), for: .touchUpInside)
    content.addArrangedSubview(refreshButton)
    let notice = weatherLabel(style: .footnote, secondary: true)
    notice.text = L("mikshat_weather_model_notice")
    attribution.isEditable = false
    attribution.isSelectable = true
    attribution.isScrollEnabled = false
    attribution.backgroundColor = .clear
    attribution.textContainerInset = .zero
    attribution.textContainer.lineFragmentPadding = 0
    attribution.adjustsFontForContentSizeCategory = true
    configureAttribution()
    content.addArrangedSubview(verticalStack([notice, attribution], spacing: 6))
  }

  private var coordinateText: String {
    String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"), coordinate.latitude, coordinate.longitude)
  }

  private func configureAttribution() {
    let text = "Open-Meteo · CC BY 4.0"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributed = NSMutableAttributedString(string: text, attributes: [
      .font: UIFont.preferredFont(forTextStyle: .footnote), .foregroundColor: UIColor.secondaryLabel,
      .paragraphStyle: paragraph,
    ])
    attributed.addAttribute(.link, value: "https://open-meteo.com/", range: (text as NSString).range(of: "Open-Meteo"))
    attributed.addAttribute(.link, value: "https://creativecommons.org/licenses/by/4.0/", range: (text as NSString).range(of: "CC BY 4.0"))
    attribution.attributedText = attributed
    attribution.linkTextAttributes = [.foregroundColor: WeatherPalette.accent, .underlineStyle: NSUnderlineStyle.single.rawValue]
  }

  @objc private func closeScreen() { stopVisibleWork(); dismiss(animated: true) }
  @objc private func refreshForecast() { loadForecast(force: true) }

  private func loadForecast(force: Bool) {
    guard isVisible else { return }
    guard coordinate.isValid else { setLoading(false); return }
    requestTask?.cancel()
    requestID = UUID()
    let identifier = requestID
    fetchFailed = false
    setLoading(true)
    requestTask = Task { [weak self] in
      guard let self else { return }
      if self.snapshot == nil, let cached = await self.repository.cached(for: self.coordinate) {
        guard self.canApplyRequest(identifier) else { return }
        self.snapshot = cached
        self.showingCache = true
        self.updateDisplayedForecast()
      }
      guard self.canApplyRequest(identifier) else { return }
      do {
        let result = try await self.repository.refresh(for: self.coordinate, force: force)
        guard self.canApplyRequest(identifier) else { return }
        let reusedCache = self.showingCache && self.snapshot?.fetchedAt == result.fetchedAt
        self.snapshot = result
        self.showingCache = reusedCache
        self.fetchFailed = false
        self.setLoading(false)
        self.updateDisplayedForecast()
      } catch {
        guard self.canApplyRequest(identifier) else { return }
        self.showingCache = self.snapshot != nil
        self.fetchFailed = true
        self.setLoading(false)
        self.updateDisplayedForecast()
      }
    }
  }

  private func canApplyRequest(_ identifier: UUID) -> Bool {
    isVisible && requestID == identifier && !Task.isCancelled
  }

  private func setLoading(_ loading: Bool) {
    isLoading = loading
    loading ? spinner.startAnimating() : spinner.stopAnimating()
    spinner.isHidden = !loading
    refreshButton.isEnabled = !loading && coordinate.isValid
    refreshButton.configuration?.showsActivityIndicator = loading
    updateStatus()
  }

  private func updateStatus() {
    if !coordinate.isValid { statusLabel.text = L("mikshat_weather_invalid_location") }
    else if isLoading { statusLabel.text = L(snapshot == nil ? "mikshat_weather_loading" : "mikshat_weather_updating") }
    else if isOnline == false { statusLabel.text = L(snapshot == nil ? "mikshat_weather_no_saved_forecast" : "mikshat_weather_offline_saved") }
    else if fetchFailed { statusLabel.text = L(snapshot == nil ? "mikshat_weather_no_saved_retry" : "mikshat_weather_refresh_failed_saved") }
    else { statusLabel.text = nil }
    statusStack.isHidden = statusLabel.text == nil
  }

  private func updateDisplayedForecast() {
    guard isViewLoaded else { return }
    updateStatus()
    guard let snapshot else { setForecastVisible(false); return }
    setForecastVisible(true)
    let condition = MikshatWeatherCondition(code: snapshot.current.weatherCode, isDay: snapshot.current.isDay)
    currentIcon.image = weatherImage(condition.symbolName)
    conditionLabel.text = L(condition.localizationKey)
    updateCurrentTemperature(snapshot.current.temperatureC)
    temperatureLabel.accessibilityLabel = String(format: L("mikshat_weather_temperature_accessibility"), number(snapshot.current.temperatureC))
    rebuildCurrentWind(snapshot.current)
    let cached = showingCache || fetchFailed || isOnline == false || !snapshot.isFresh(at: Date())
    cacheLabel.text = cached ? L("mikshat_weather_saved_data") : nil
    cacheLabel.isHidden = !cached
    let updated = DateFormatter()
    updated.locale = .current
    updated.timeZone = snapshot.timeZone
    updated.dateStyle = .medium
    updated.timeStyle = .short
    updatedLabel.text = String(format: L("mikshat_weather_last_updated"), updated.string(from: snapshot.fetchedAt))
    rebuildHourly(snapshot)
  }

  private func updateCurrentTemperature(_ value: Double?) {
    if let value, value.isFinite {
      let accessibilitySize = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
      temperatureLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
        for: .systemFont(ofSize: 48, weight: .semibold), maximumPointSize: 100, compatibleWith: traitCollection)
      temperatureLabel.numberOfLines = accessibilitySize ? 2 : 1
      temperatureLabel.text = temperature(value).replacingOccurrences(of: "\u{00a0}",
                                                                     with: accessibilitySize ? "\n" : "\u{00a0}")
    } else {
      temperatureLabel.font = .preferredFont(forTextStyle: .title2, compatibleWith: traitCollection)
      temperatureLabel.numberOfLines = 0
      temperatureLabel.text = L("mikshat_weather_unavailable")
    }
  }

  private func setForecastVisible(_ visible: Bool) {
    if visible {
      if !content.arrangedSubviews.contains(currentCard) { content.insertArrangedSubview(currentCard, at: 2) }
      if !content.arrangedSubviews.contains(hourlySection) { content.insertArrangedSubview(hourlySection, at: 3) }
      currentCard.isHidden = false
      hourlySection.isHidden = false
    } else {
      // Detach empty sections so UIStackView never imposes zero height on measured cards.
      for section in [currentCard, hourlySection] as [UIView] {
        content.removeArrangedSubview(section)
        section.removeFromSuperview()
        section.isHidden = true
      }
    }
  }

  private func rebuildCurrentWind(_ sample: MikshatWeatherSample) {
    removeArrangedViews(from: windStack)
    windStack.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
    windStack.addArrangedSubview(metric(title: L("mikshat_weather_wind_speed"), value: windSpeed(sample.windSpeedKmh)))
    windStack.addArrangedSubview(windSource(sample))
    windStack.addArrangedSubview(metric(title: L("mikshat_weather_gusts"), value: windSpeed(sample.windGustsKmh)))
  }

  private func rebuildHourly(_ snapshot: MikshatWeatherSnapshot) {
    hourlyScroll.prepareForRebuild()
    removeArrangedViews(from: hourlyStack)
    let hours = snapshot.futureHours()
    hourlyAvailability.text = hours.count < 12 ? String(format: L("mikshat_weather_available_hours"), hours.count) : nil
    hourlyAvailability.isHidden = hours.count == 12
    hourlyScroll.isHidden = hours.isEmpty
    let time = DateFormatter()
    time.locale = .current
    time.timeZone = snapshot.timeZone
    time.dateStyle = .none
    time.timeStyle = .short
    let day = DateFormatter()
    day.locale = .current
    day.timeZone = snapshot.timeZone
    day.setLocalizedDateFormatFromTemplate("EEEdMMM")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = snapshot.timeZone
    let now = Date()
    for sample in hours {
      let condition = MikshatWeatherCondition(code: sample.weatherCode, isDay: sample.isDay)
      let card = WeatherCard()
      let timeLabel = weatherLabel(style: .headline)
      timeLabel.text = time.string(from: sample.time)
      let dateLabel = weatherLabel(style: .caption1, secondary: true)
      dateLabel.text = calendar.isDate(sample.time, inSameDayAs: now) ? nil : day.string(from: sample.time)
      dateLabel.isHidden = dateLabel.text == nil
      let icon = UIImageView(image: weatherImage(condition.symbolName))
      icon.contentMode = .scaleAspectFit
      icon.tintColor = WeatherPalette.accent
      icon.isAccessibilityElement = false
      icon.heightAnchor.constraint(equalToConstant: 36).isActive = true
      let description = weatherLabel(style: .subheadline)
      description.text = L(condition.localizationKey)
      let degrees = weatherLabel(style: .title2)
      degrees.text = temperature(sample.temperatureC)
      degrees.numberOfLines = 1
      degrees.adjustsFontSizeToFitWidth = true
      degrees.minimumScaleFactor = 0.65
      degrees.semanticContentAttribute = .forceLeftToRight
      let speed = weatherLabel(style: .subheadline)
      speed.text = String(format: L("mikshat_weather_hour_wind"), windSpeed(sample.windSpeedKmh))
      var items: [UIView] = [timeLabel, dateLabel, icon, description, degrees, speed, windSource(sample, compact: true)]
      if let gusts = sample.windGustsKmh {
        let gust = weatherLabel(style: .caption1, secondary: true)
        gust.text = String(format: L("mikshat_weather_hour_gusts"), windSpeed(gusts))
        items.append(gust)
      }
      card.install(verticalStack(items, spacing: 8), inset: 12)
      let scaledWidth = UIFontMetrics(forTextStyle: .body).scaledValue(for: 166, compatibleWith: traitCollection)
      let availableWidth = scrollView.bounds.width > 0 ? scrollView.bounds.width : view.bounds.width
      card.widthAnchor.constraint(equalToConstant: min(scaledWidth, max(166, availableWidth - 64))).isActive = true
      card.isAccessibilityElement = true
      card.accessibilityIdentifier = "weather.hour.\(Int(sample.time.timeIntervalSince1970))"
      let wind = MikshatWeatherWind(speedKmh: sample.windSpeedKmh, directionDegrees: sample.windDirectionDegrees)
      var accessible = [day.string(from: sample.time), time.string(from: sample.time), L(condition.localizationKey),
                        String(format: L("mikshat_weather_temperature_accessibility"), number(sample.temperatureC)),
                        speed.text ?? "", windDescription(wind)]
      if let gusts = sample.windGustsKmh { accessible.append(String(format: L("mikshat_weather_hour_gusts"), windSpeed(gusts))) }
      card.accessibilityLabel = accessible.joined(separator: ", ")
      hourlyStack.addArrangedSubview(card)
    }
    hourlyScroll.setNeedsLayout()
    view.setNeedsLayout()
  }

  private func metric(title: String, value: String) -> UIView {
    let titleLabel = weatherLabel(style: .caption1, secondary: true)
    titleLabel.text = title
    let valueLabel = weatherLabel(style: .body)
    valueLabel.text = value
    let stack = verticalStack([titleLabel, valueLabel], spacing: 5)
    stack.isAccessibilityElement = true
    stack.accessibilityLabel = title + ", " + value
    return stack
  }

  private func windSource(_ sample: MikshatWeatherSample, compact: Bool = false) -> UIView {
    let wind = MikshatWeatherWind(speedKmh: sample.windSpeedKmh, directionDegrees: sample.windDirectionDegrees)
    let label = weatherLabel(style: compact ? .caption1 : .body)
    label.text = windDescription(wind)
    var items: [UIView] = []
    if let bearing = wind.bearingDegrees {
      let arrow = UIImageView(image: UIImage(systemName: "arrow.up"))
      arrow.tintColor = WeatherPalette.accent
      arrow.contentMode = .scaleAspectFit
      arrow.isAccessibilityElement = false
      arrow.transform = CGAffineTransform(rotationAngle: CGFloat(bearing * .pi / 180))
      let container = UIView()
      arrow.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(arrow)
      NSLayoutConstraint.activate([
        arrow.widthAnchor.constraint(equalToConstant: 23), arrow.heightAnchor.constraint(equalToConstant: 23),
        arrow.centerXAnchor.constraint(equalTo: container.centerXAnchor), arrow.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        container.heightAnchor.constraint(equalToConstant: 29),
      ])
      items.append(container)
    }
    items.append(label)
    let result = verticalStack(items, spacing: 4)
    result.isAccessibilityElement = true
    result.accessibilityLabel = label.text
    return result
  }

  private func windDescription(_ wind: MikshatWeatherWind) -> String {
    let direction = L(wind.localizationKey)
    return wind.bearingDegrees == nil ? direction : String(format: L("mikshat_weather_wind_from"), direction)
  }

  private func startMonitoringConnectivity() {
    guard pathMonitor == nil else { return }
    connectivityID = UUID()
    let identifier = connectivityID
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      let online = path.status == .satisfied
      Task { @MainActor [weak self] in
        guard let self, self.isVisible, self.connectivityID == identifier else { return }
        let wasOffline = self.isOnline == false
        self.isOnline = online
        self.updateDisplayedForecast()
        if wasOffline && online { self.loadForecast(force: true) }
      }
    }
    pathMonitor = monitor
    monitor.start(queue: DispatchQueue(label: "app.mikshat.weather.connectivity", qos: .utility))
  }

  private func stopVisibleWork() {
    isVisible = false
    requestID = UUID()
    connectivityID = UUID()
    requestTask?.cancel()
    requestTask = nil
    pathMonitor?.cancel()
    pathMonitor = nil
    isOnline = nil
    displayTimer?.invalidate()
    displayTimer = nil
  }
}

/// Own the position after UIScrollView has measured and clamped its content, rather than in the
/// controller's earlier layout callback. A timestamp anchor survives rebuilt cards and rotation.
@MainActor
private final class WeatherHoursScrollView: UIScrollView, UIScrollViewDelegate {
  weak var cards: UIStackView?
  private enum Position {
    case first
    case hour(identifier: String, rightFraction: CGFloat)
  }
  private var position = Position.first
  private var awaitingContentLayout = true
  private var isLayingOutContent = false
  private var laidOutWidth: CGFloat = 0
  private var laidOutContentWidth: CGFloat = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    delegate = self
    // The outer weather page already respects the screen's safe areas.
    contentInsetAdjustmentBehavior = .never
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func prepareForRebuild() {
    capturePosition()
    awaitingContentLayout = true
  }

  override func layoutSubviews() {
    guard !isLayingOutContent else { return }
    isLayingOutContent = true
    defer { isLayingOutContent = false }
    super.layoutSubviews()
    guard let cards, !cards.arrangedSubviews.isEmpty else { return }
    cards.layoutIfNeeded()
    // Intermediate zero/fit layouts must not consume the initial first-hour position.
    guard bounds.width > 0, bounds.height > 0, cards.bounds.width > 0,
          abs(contentSize.width - cards.bounds.width) < 1,
          cards.arrangedSubviews.allSatisfy({ $0.bounds.width > 0 && $0.bounds.height > 0 }) else { return }
    laidOutWidth = bounds.width
    laidOutContentWidth = contentSize.width
    awaitingContentLayout = false
    guard !isTracking, !isDragging, !isDecelerating else { return }
    let minimum = -adjustedContentInset.left
    let maximum = max(minimum, contentSize.width - bounds.width + adjustedContentInset.right)
    let target: CGFloat
    switch position {
    case .first:
      target = maximum
    case let .hour(identifier, fraction):
      if let card = cards.arrangedSubviews.first(where: { $0.accessibilityIdentifier == identifier }) {
        let rect = card.convert(card.bounds, to: self)
        target = min(maximum, max(minimum, rect.maxX - fraction * rect.width - bounds.width + adjustedContentInset.right))
      } else {
        // The previously visible hour expired; show the first surviving future hour.
        position = .first
        target = maximum
      }
    }
    // The pending flag is already clear: changing bounds may schedule another layout callback.
    if abs(contentOffset.x - target) > 0.5 {
      super.setContentOffset(CGPoint(x: target, y: contentOffset.y), animated: false)
    }
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) { capturePosition() }

  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    capturePosition()
    if !decelerate { setNeedsLayout() }
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    capturePosition()
    setNeedsLayout()
  }

  private func capturePosition() {
    // Only non-owned scrolling of settled geometry represents user/accessibility intent.
    guard !isLayingOutContent, !awaitingContentLayout, let cards,
          abs(bounds.width - laidOutWidth) < 0.5,
          abs(contentSize.width - laidOutContentWidth) < 0.5 else { return }
    let maximum = max(-adjustedContentInset.left, contentSize.width - bounds.width + adjustedContentInset.right)
    if abs(contentOffset.x - maximum) < 1 {
      position = .first
      return
    }
    let right = contentOffset.x + bounds.width - adjustedContentInset.right
    let left = contentOffset.x + adjustedContentInset.left
    guard let card = cards.arrangedSubviews.first(where: {
      let rect = $0.convert($0.bounds, to: self)
      return rect.minX < right && rect.maxX > left
    }), let identifier = card.accessibilityIdentifier else { return }
    let rect = card.convert(card.bounds, to: self)
    guard rect.width > 0 else { return }
    position = .hour(identifier: identifier, rightFraction: (rect.maxX - right) / rect.width)
  }
}

private enum WeatherPalette {
  static let background = UIColor { $0.userInterfaceStyle == .dark ? MikshatStyle.night : MikshatStyle.cream }
  static let card = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.06, green: 0.16, blue: 0.19, alpha: 1) : .white }
  static let accent = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.62, green: 0.86, blue: 0.72, alpha: 1) : MikshatStyle.green }
  static let border = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.22) : UIColor(red: 0.82, green: 0.86, blue: 0.81, alpha: 1) }
  static let buttonText = UIColor { $0.userInterfaceStyle == .dark ? MikshatStyle.night : .white }
}

@MainActor
private final class WeatherCard: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = WeatherPalette.card
    layer.cornerRadius = 20
    layer.borderWidth = 1
    updateBorder()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    updateBorder()
  }
  func updateBorder() { layer.borderColor = WeatherPalette.border.resolvedColor(with: traitCollection).cgColor }
  func install(_ contents: UIView, inset: CGFloat = 18) {
    contents.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contents)
    NSLayoutConstraint.activate([
      contents.topAnchor.constraint(equalTo: topAnchor, constant: inset),
      contents.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
      contents.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
      contents.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
    ])
  }
}

@MainActor
private func weatherLabel(style: UIFont.TextStyle, secondary: Bool = false) -> UILabel {
  let label = UILabel()
  label.font = .preferredFont(forTextStyle: style)
  label.adjustsFontForContentSizeCategory = true
  label.textColor = secondary ? .secondaryLabel : .label
  label.textAlignment = .center
  label.numberOfLines = 0
  return label
}

@MainActor
private func verticalStack(_ views: [UIView], spacing: CGFloat) -> UIStackView {
  let stack = UIStackView(arrangedSubviews: views)
  stack.axis = .vertical
  stack.spacing = spacing
  return stack
}

@MainActor
private func removeArrangedViews(from stack: UIStackView) {
  for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
}

@MainActor
private func weatherImage(_ name: String) -> UIImage? {
  UIImage(systemName: name) ?? UIImage(systemName: "questionmark.circle")
}

private func number(_ value: Double?) -> String {
  guard let value, value.isFinite else { return L("mikshat_weather_unavailable") }
  let formatter = NumberFormatter()
  formatter.locale = .current
  formatter.numberStyle = .decimal
  formatter.maximumFractionDigits = 0
  formatter.usesGroupingSeparator = false
  return formatter.string(from: NSNumber(value: value)) ?? L("mikshat_weather_unavailable")
}

private func temperature(_ value: Double?) -> String {
  guard let value, value.isFinite else { return L("mikshat_weather_unavailable") }
  return number(value) + "\u{00a0}°C"
}

private func windSpeed(_ value: Double?) -> String {
  guard let value, value.isFinite, value >= 0 else { return L("mikshat_weather_unavailable") }
  // A narrow metric may move its complete unit to a second line without splitting that unit.
  return number(value) + " " + L("mikshat_kmh").replacingOccurrences(of: " ", with: "\u{00a0}")
}
