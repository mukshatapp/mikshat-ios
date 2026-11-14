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
  private let currentColumn = UIStackView()
  private let forecastColumn = UIStackView()
  private let currentSummary = UIStackView()
  private let statusStack = UIStackView()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let statusLabel = weatherLabel(style: .caption1, secondary: true)
  private let currentCard = WeatherCard()
  private let currentStack = UIStackView()
  private let currentIcon = UIImageView()
  private let conditionLabel = weatherLabel(style: .subheadline)
  private let temperatureLabel = weatherLabel(style: .largeTitle)
  private let windStack = UIStackView()
  private let cacheLabel = weatherLabel(style: .caption1, secondary: true)
  private let updatedLabel = weatherLabel(style: .caption1, secondary: true)
  private let currentMetadata = UIStackView()
  private let hourlySection = UIStackView()
  private let hourlyScroll = WeatherHoursScrollView()
  private let hourlyStack = UIStackView()
  private let hourlyAvailability = weatherLabel(style: .footnote, secondary: true)
  private let refreshButton = UIButton(type: .system)
  private let attribution = UITextView()
  private let sourceFooter = UIStackView()
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
  private var contentMaximumWidth: NSLayoutConstraint?
  private var hourlyHeight: NSLayoutConstraint?
  private var usesColumns = false
  private var usesStatusColumns = false

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
    updateResponsiveLayout()
    let availableWidth = hourlySection.bounds.width
    if abs(lastLayoutWidth - availableWidth) > 1 {
      lastLayoutWidth = availableWidth
      if let snapshot { rebuildHourly(snapshot) }
    }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
      updateResponsiveLayout()
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
    scrollView.alwaysBounceVertical = false
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.accessibilityIdentifier = "weather.scroll"
    scrollView.keyboardDismissMode = .onDrag
    view.addSubview(scrollView)
    content.axis = .vertical
    content.spacing = 8
    content.accessibilityIdentifier = "weather.content"
    content.translatesAutoresizingMaskIntoConstraints = false
    let canvas = UIView()
    canvas.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(canvas)
    canvas.addSubview(content)
    // The canvas grows when text needs more room, while shorter pages stay centered in the
    // actual presentation bounds (including a resizable sheet or an iPad split view).
    let viewportHeight = canvas.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
    viewportHeight.priority = UILayoutPriority(249)
    let preferredWidth = content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -24)
    preferredWidth.priority = UILayoutPriority(999)
    let maximumWidth = content.widthAnchor.constraint(lessThanOrEqualToConstant: 560)
    contentMaximumWidth = maximumWidth
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
      header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      close.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
      close.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      canvas.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      canvas.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      canvas.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      canvas.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      canvas.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
      canvas.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
      viewportHeight,
      content.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
      content.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
      content.topAnchor.constraint(greaterThanOrEqualTo: canvas.topAnchor, constant: 4),
      content.bottomAnchor.constraint(lessThanOrEqualTo: canvas.bottomAnchor, constant: -4),
      preferredWidth,
      maximumWidth,
    ])
    for column in [currentColumn, forecastColumn] {
      column.axis = .vertical
      column.spacing = 4
      content.addArrangedSubview(column)
    }
    let location = weatherLabel(style: .headline)
    location.text = locationName
    location.accessibilityIdentifier = "weather.location"
    location.accessibilityTraits.insert(.header)
    let coordinates = weatherLabel(style: .caption1, secondary: true)
    coordinates.text = coordinateText
    coordinates.accessibilityIdentifier = "weather.coordinates"
    coordinates.semanticContentAttribute = .forceLeftToRight
    coordinates.accessibilityLabel = String(format: L("mikshat_weather_coordinates"), coordinateText)
    currentColumn.addArrangedSubview(verticalStack([location, coordinates], spacing: 2))
    statusStack.axis = .horizontal
    statusStack.alignment = .center
    statusStack.spacing = 10
    statusStack.addArrangedSubview(spinner)
    statusStack.addArrangedSubview(statusLabel)
    statusLabel.accessibilityTraits.insert(.updatesFrequently)
    statusLabel.accessibilityIdentifier = "weather.status"
    currentColumn.addArrangedSubview(statusStack)
    currentStack.axis = .vertical
    currentStack.alignment = .fill
    currentStack.spacing = 4
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
      currentIcon.widthAnchor.constraint(equalToConstant: 38),
      currentIcon.heightAnchor.constraint(equalToConstant: 32),
    ])
    conditionLabel.accessibilityIdentifier = "weather.current.condition"
    let condition = verticalStack([iconContainer, conditionLabel], spacing: 2)
    currentSummary.axis = .horizontal
    currentSummary.alignment = .center
    currentSummary.distribution = .fillEqually
    currentSummary.spacing = 8
    currentSummary.accessibilityIdentifier = "weather.current.summary"
    currentSummary.addArrangedSubview(condition)
    currentSummary.addArrangedSubview(temperatureLabel)
    currentStack.addArrangedSubview(currentSummary)
    temperatureLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: .systemFont(ofSize: 40, weight: .semibold))
    temperatureLabel.textColor = WeatherPalette.accent
    temperatureLabel.numberOfLines = 1
    temperatureLabel.adjustsFontSizeToFitWidth = true
    temperatureLabel.minimumScaleFactor = 0.65
    temperatureLabel.semanticContentAttribute = .forceLeftToRight
    temperatureLabel.accessibilityIdentifier = "weather.current.temperature"
    windStack.spacing = 6
    windStack.distribution = .fillEqually
    currentStack.addArrangedSubview(windStack)
    cacheLabel.font = .preferredFont(forTextStyle: .subheadline)
    cacheLabel.textColor = WeatherPalette.accent
    cacheLabel.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
    currentMetadata.axis = .horizontal
    currentMetadata.alignment = .center
    currentMetadata.spacing = 4
    currentMetadata.addArrangedSubview(cacheLabel)
    currentMetadata.addArrangedSubview(updatedLabel)
    currentStack.addArrangedSubview(currentMetadata)
    currentCard.install(currentStack, inset: 8)
    currentCard.accessibilityIdentifier = "weather.current"
    cacheLabel.accessibilityIdentifier = "weather.saved"
    updatedLabel.accessibilityIdentifier = "weather.updated"
    currentCard.isHidden = true
    hourlySection.axis = .vertical
    hourlySection.spacing = 5
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
    let measuredHeight = hourlyScroll.heightAnchor.constraint(equalToConstant: 150)
    measuredHeight.isActive = true
    hourlyHeight = measuredHeight
    hourlySection.addArrangedSubview(hourlyAvailability)
    hourlySection.isHidden = true
    var configuration = UIButton.Configuration.filled()
    configuration.title = L("mikshat_weather_refresh")
    configuration.image = UIImage(systemName: "arrow.clockwise")
    configuration.imagePadding = 10
    configuration.baseBackgroundColor = WeatherPalette.accent
    configuration.baseForegroundColor = WeatherPalette.buttonText
    configuration.cornerStyle = .large
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var result = attributes
      result.font = UIFont.preferredFont(forTextStyle: .headline)
      return result
    }
    refreshButton.configuration = configuration
    refreshButton.accessibilityIdentifier = "weather.refresh"
    refreshButton.titleLabel?.numberOfLines = 0
    refreshButton.titleLabel?.adjustsFontForContentSizeCategory = true
    refreshButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    refreshButton.addTarget(self, action: #selector(refreshForecast), for: .touchUpInside)
    forecastColumn.addArrangedSubview(refreshButton)
    let notice = weatherLabel(style: .caption1, secondary: true)
    notice.text = L("mikshat_weather_model_notice")
    notice.accessibilityIdentifier = "weather.notice"
    attribution.isEditable = false
    attribution.isSelectable = true
    attribution.isScrollEnabled = false
    attribution.backgroundColor = .clear
    attribution.textContainerInset = .zero
    attribution.textContainer.lineFragmentPadding = 0
    attribution.adjustsFontForContentSizeCategory = true
    attribution.accessibilityIdentifier = "weather.attribution"
    configureAttribution()
    sourceFooter.axis = .vertical
    sourceFooter.spacing = 2
    sourceFooter.addArrangedSubview(notice)
    sourceFooter.addArrangedSubview(attribution)
    forecastColumn.addArrangedSubview(sourceFooter)
  }

  private func updateResponsiveLayout() {
    guard isViewLoaded else { return }
    let available = view.safeAreaLayoutGuide.layoutFrame.size
    let accessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    let columns = available.width > available.height && available.width >= 480 && !accessibility
    let statusColumns = columns && !statusStack.isHidden
    currentSummary.axis = accessibility ? .vertical : .horizontal
    currentSummary.alignment = accessibility ? .fill : .center
    currentSummary.distribution = accessibility ? .fill : .fillEqually
    currentMetadata.axis = accessibility ? .vertical : .horizontal
    currentMetadata.alignment = accessibility ? .fill : .center
    contentMaximumWidth?.constant = columns ? 1000 : 560
    guard columns != usesColumns || statusColumns != usesStatusColumns else { return }
    usesColumns = columns
    usesStatusColumns = statusColumns
    content.axis = columns ? .horizontal : .vertical
    content.alignment = columns ? .center : .fill
    content.distribution = columns ? .fillEqually : .fill
    content.spacing = columns ? 14 : 8
    // Balance the extra offline/updating copy across the two columns as it appears. The
    // action and licensing links remain visible without reserving empty status space.
    (refreshButton.superview as? UIStackView)?.removeArrangedSubview(refreshButton)
    refreshButton.removeFromSuperview()
    (attribution.superview as? UIStackView)?.removeArrangedSubview(attribution)
    attribution.removeFromSuperview()
    if statusColumns {
      currentColumn.addArrangedSubview(attribution)
      forecastColumn.insertArrangedSubview(refreshButton, at: hourlySection.superview == nil ? 0 : 1)
    } else {
      sourceFooter.addArrangedSubview(attribution)
      if columns { currentColumn.addArrangedSubview(refreshButton) }
      else { forecastColumn.insertArrangedSubview(refreshButton, at: hourlySection.superview == nil ? 0 : 1) }
    }
  }

  private var coordinateText: String {
    String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"), coordinate.latitude, coordinate.longitude)
  }

  private func configureAttribution() {
    let text = "Open-Meteo · CC BY 4.0"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributed = NSMutableAttributedString(string: text, attributes: [
      .font: UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection), .foregroundColor: UIColor.secondaryLabel,
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
        for: .systemFont(ofSize: 40, weight: .semibold), maximumPointSize: 100, compatibleWith: traitCollection)
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
      if !currentColumn.arrangedSubviews.contains(currentCard) { currentColumn.insertArrangedSubview(currentCard, at: 2) }
      if !forecastColumn.arrangedSubviews.contains(hourlySection) { forecastColumn.insertArrangedSubview(hourlySection, at: 0) }
      currentCard.isHidden = false
      hourlySection.isHidden = false
    } else {
      // Detach empty sections so UIStackView never imposes zero height on measured cards.
      for section in [currentCard, hourlySection] as [UIView] {
        (section.superview as? UIStackView)?.removeArrangedSubview(section)
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
    var maximumCardHeight: CGFloat = 0
    let accessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    let scaledWidth = UIFontMetrics(forTextStyle: .body).scaledValue(for: 216, compatibleWith: traitCollection)
    let availableWidth = hourlySection.bounds.width > 0 ? hourlySection.bounds.width : max(166, view.bounds.width - 24)
    let cardWidth = min(scaledWidth, max(166, availableWidth - 24))
    for sample in hours {
      let condition = MikshatWeatherCondition(code: sample.weatherCode, isDay: sample.isDay)
      let card = WeatherCard()
      let timeLabel = forecastLabel(style: .subheadline)
      timeLabel.text = time.string(from: sample.time)
      let dateLabel = forecastLabel(style: .caption1, secondary: true)
      dateLabel.text = calendar.isDate(sample.time, inSameDayAs: now) ? nil : day.string(from: sample.time)
      dateLabel.isHidden = dateLabel.text == nil
      let icon = UIImageView(image: weatherImage(condition.symbolName))
      icon.contentMode = .scaleAspectFit
      icon.tintColor = WeatherPalette.accent
      icon.isAccessibilityElement = false
      icon.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        icon.heightAnchor.constraint(equalToConstant: 26),
        icon.widthAnchor.constraint(equalToConstant: 30),
      ])
      let description = forecastLabel(style: .subheadline)
      description.text = L(condition.localizationKey)
      let degrees = forecastLabel(style: .title3)
      degrees.text = temperature(sample.temperatureC)
      degrees.numberOfLines = 1
      degrees.adjustsFontSizeToFitWidth = true
      degrees.minimumScaleFactor = 0.65
      degrees.semanticContentAttribute = .forceLeftToRight
      let speed = forecastLabel(style: .caption1)
      speed.text = String(format: L("mikshat_weather_hour_wind"), windSpeed(sample.windSpeedKmh))
      // A compact horizontal heading reduces card height without omitting any of the 12 hours
      // or their wind and condition fields. Accessibility sizes retain generous vertical rows.
      let itemsHeader: [UIView]
      if accessibility {
        itemsHeader = [timeLabel, dateLabel, icon, description, degrees]
      } else {
        let timeAndTemperature = UIStackView(arrangedSubviews: [verticalStack([timeLabel, dateLabel], spacing: 2), degrees])
        timeAndTemperature.alignment = .center
        timeAndTemperature.spacing = 4
        timeAndTemperature.distribution = .fillEqually
        let conditionRow = UIStackView(arrangedSubviews: [icon, description])
        conditionRow.alignment = .center
        conditionRow.spacing = 4
        itemsHeader = [timeAndTemperature, conditionRow]
      }
      var windItems: [UIView] = [speed]
      if let gusts = sample.windGustsKmh {
        let gust = forecastLabel(style: .caption1, secondary: true)
        gust.text = String(format: L("mikshat_weather_hour_gusts"), windSpeed(gusts))
        windItems.append(gust)
      }
      let items: [UIView]
      if accessibility {
        items = itemsHeader + windItems + [windSource(sample, compact: true)]
      } else {
        let windRow = UIStackView(arrangedSubviews: windItems)
        windRow.axis = .horizontal
        windRow.alignment = .center
        windRow.distribution = .fillEqually
        windRow.spacing = 4
        items = itemsHeader + [windRow, windSource(sample, compact: true)]
      }
      card.install(verticalStack(items, spacing: 3), inset: 8)
      card.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
      // UIScrollView has no intrinsic height. Measure the complete card at its real width so
      // wrapped localized labels and Dynamic Type expand the page instead of being clipped.
      let measured = card.systemLayoutSizeFitting(CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
                                                  withHorizontalFittingPriority: .required,
                                                  verticalFittingPriority: .fittingSizeLevel)
      maximumCardHeight = max(maximumCardHeight, ceil(measured.height))
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
    hourlyHeight?.constant = maximumCardHeight + 10
    hourlyScroll.setNeedsLayout()
    view.setNeedsLayout()
  }

  private func metric(title: String, value: String) -> UIView {
    let titleLabel = forecastLabel(style: .caption1, secondary: true)
    titleLabel.text = title
    let valueLabel = forecastLabel(style: .subheadline)
    valueLabel.text = value
    let stack = verticalStack([titleLabel, valueLabel], spacing: 2)
    stack.isAccessibilityElement = true
    stack.accessibilityLabel = title + ", " + value
    return stack
  }

  private func windSource(_ sample: MikshatWeatherSample, compact: Bool = false) -> UIView {
    let wind = MikshatWeatherWind(speedKmh: sample.windSpeedKmh, directionDegrees: sample.windDirectionDegrees)
    let label = forecastLabel(style: .caption1)
    label.text = windDescription(wind)
    var items: [UIView] = []
    if let bearing = wind.bearingDegrees {
      let arrow = UIImageView(image: UIImage(systemName: "arrow.up"))
      arrow.tintColor = WeatherPalette.accent
      arrow.contentMode = .scaleAspectFit
      arrow.isAccessibilityElement = false
      arrow.transform = CGAffineTransform(rotationAngle: CGFloat(bearing * .pi / 180))
      let container = UIView()
      let arrowSize: CGFloat = compact ? 14 : 16
      let containerSize: CGFloat = compact ? 18 : 20
      arrow.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(arrow)
      NSLayoutConstraint.activate([
        arrow.widthAnchor.constraint(equalToConstant: arrowSize), arrow.heightAnchor.constraint(equalToConstant: arrowSize),
        arrow.centerXAnchor.constraint(equalTo: container.centerXAnchor), arrow.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        container.widthAnchor.constraint(equalToConstant: containerSize),
        container.heightAnchor.constraint(equalToConstant: containerSize),
      ])
      items.append(container)
    }
    items.append(label)
    let result = UIStackView(arrangedSubviews: items)
    result.axis = .horizontal
    result.alignment = .center
    result.spacing = 3
    result.isAccessibilityElement = true
    result.accessibilityLabel = label.text
    return result
  }

  private func windDescription(_ wind: MikshatWeatherWind) -> String {
    let direction = L(wind.localizationKey)
    return wind.bearingDegrees == nil ? direction : String(format: L("mikshat_weather_wind_from"), direction)
  }

  private func forecastLabel(style: UIFont.TextStyle, secondary: Bool = false) -> UILabel {
    let label = weatherLabel(style: style, secondary: secondary)
    // Cards are measured before being attached; inherit this controller's current text size
    // explicitly rather than measuring once with the default trait environment.
    label.font = .preferredFont(forTextStyle: style, compatibleWith: traitCollection)
    return label
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
