final class NavigationControlView: SolidTouchView {
  private enum Constants {
    static let buttonContentInset: CGFloat = 15
    static var metricFont: UIFont { UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 38, weight: .regular)) }
    static var metricLegendFont: UIFont { UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 18, weight: .regular)) }
  }

  @IBOutlet private var distanceLabel: UILabel!
  @IBOutlet private var distanceLegendLabel: UILabel!
  @IBOutlet private var distanceWithLegendLabel: UILabel!
  @IBOutlet private var progressView: UIView!
  @IBOutlet private var routingProgress: NSLayoutConstraint!
  @IBOutlet private var speedLabel: UILabel!
  @IBOutlet private var speedBackground: UIView!
  @IBOutlet private var speedLegendLabel: UILabel!
  @IBOutlet private var speedWithLegendLabel: UILabel!
  @IBOutlet private var timeLabel: UILabel!
  @IBOutlet private var timePageControl: UIPageControl!
  @IBOutlet private var extendedView: UIView!

  @IBOutlet private var extendButton: UIButton! {
    didSet {
      setExtendButtonImage()
    }
  }

  @IBOutlet private var settingsButton: MWMButton!
  @IBOutlet private var stopButton: UIButton!

  @IBOutlet private var ttsButton: MWMButton! {
    didSet {
      ttsButton.setImage(UIImage.icVoiceOff, for: .normal)
      ttsButton.setImage(UIImage.icVoiceOn, for: .selected)
      ttsButton.setImage(UIImage.icVoiceOn, for: [.selected, .highlighted])
      onTTSStatusUpdated()
    }
  }

  @IBOutlet private var trackRecordingButton: MWMButton!

  private lazy var dimBackground: DimBackground = .init(mainView: self, tapAction: { [weak self] in
    self?.diminish()
  })

  weak var ownerView: UIView!
  weak var delegate: RouteNavigationControlsDelegate!

  private weak var navigationInfo: MWMNavigationDashboardEntity?
  private var placementConstraints: [NSLayoutConstraint] = []
  private var placementSize = CGSize.zero
  private var placementSafeArea = UIEdgeInsets.zero
  private var placementRailWidth: CGFloat = 0
  private let diminishSelector = #selector(diminish)

  var isVisible = false {
    didSet {
      guard isVisible != oldValue else { return }
      if isVisible {
        addView()
      } else {
        removeView()
      }
    }
  }

  private var isExtended = false {
    willSet {
      guard isExtended != newValue else { return }
      // The centered grabber replaces the old three-line button.
    }
    didSet {
      guard isVisible, superview != nil, isExtended != oldValue else { return }

      dimBackground.setVisible(isExtended, completion: nil)
      extendedView.isHidden = !isExtended
      superview!.animateConstraints(animations: { [weak self] in
        guard let self else { return }
        self.superview?.layoutIfNeeded()
      })
    }
  }

  private var metricsLabels: [UILabel] {
    [distanceLabel, distanceWithLegendLabel, speedLabel, speedWithLegendLabel, timeLabel]
  }

  private var metricsLegendLabels: [UILabel] {
    [distanceLegendLabel, speedLegendLabel]
  }

  private var mikshatActions: MikshatNavigationActionsView?
  private var lastViewportInsets = UIEdgeInsets.zero
  private var legacyViews: [UIView] = []
  private let timeLegend = MikshatStyle.label(size: 18, color: .gray)
  private var navigationActionsRow: UIStackView!
  private var secondaryActionsRow: UIStackView?
  private var narrowActions = false

  override func awakeFromNib() {
    super.awakeFromNib()
    accessibilityIdentifier = "navigation.infoCard"
    buildMikshatPanel()

    for label in metricsLabels {
      configureMetricLabel(label, font: Constants.metricFont)
    }
    for label in metricsLegendLabels {
      configureMetricLabel(label, font: Constants.metricLegendFont)
    }
    updateLegendSize()

    configureButton(settingsButton)
    configureButton(ttsButton)
    configureButton(trackRecordingButton)
    trackRecordingButton.isHidden = true
    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(mikshatPan(_:))))
    configureStopButton(stopButton)

    MWMTextToSpeech.add(self)
  }

  private func buildMikshatPanel() {
    let distance = distanceLabel!, distanceUnit = distanceLegendLabel!, speed = speedLabel!, speedUnit = speedLegendLabel!, time = timeLabel!
    let speedBox = speedBackground!, progress = progressView!, extended = extendedView!
    let stop = stopButton!, voice = ttsButton!, settings = settingsButton!
    distance.accessibilityIdentifier = "navigation.distanceValue"
    speed.accessibilityIdentifier = "navigation.speedValue"
    speedUnit.accessibilityIdentifier = "navigation.speedUnit"
    time.accessibilityIdentifier = "navigation.timeValue"
    stop.accessibilityIdentifier = "navigation.stop"
    voice.accessibilityIdentifier = "navigation.sound"
    settings.accessibilityIdentifier = "navigation.settings"
    legacyViews = [distanceWithLegendLabel, speedWithLegendLabel, timePageControl, extendButton, trackRecordingButton]
    let retained: [UIView] = [distance, distanceUnit, speed, speedUnit, time, speedBox, progress, extended, stop, voice, settings] + legacyViews
    NSLayoutConstraint.deactivate(constraints)
    retained.forEach { $0.removeFromSuperview() }
    subviews.forEach { $0.removeFromSuperview() }
    speedBox.subviews.forEach { $0.removeFromSuperview() }
    NSLayoutConstraint.deactivate(speedBox.constraints)
    extended.subviews.forEach { $0.removeFromSuperview() }
    NSLayoutConstraint.deactivate(extended.constraints)
    backgroundColor = .white
    layer.cornerRadius = 24
    layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    let grip = UIView()
    grip.backgroundColor = .lightGray
    grip.layer.cornerRadius = 3
    grip.translatesAutoresizingMaskIntoConstraints = false
    let handle = UIView()
    handle.addSubview(grip)
    NSLayoutConstraint.activate([
      handle.heightAnchor.constraint(equalToConstant: 8), grip.widthAnchor.constraint(equalToConstant: 38), grip.heightAnchor.constraint(equalToConstant: 5),
      grip.centerXAnchor.constraint(equalTo: handle.centerXAnchor), grip.centerYAnchor.constraint(equalTo: handle.centerYAnchor),
    ])
    handle.isAccessibilityElement = true
    handle.accessibilityIdentifier = "navigation.expand"
    handle.accessibilityLabel = L("mikshat_show_stop")
    handle.accessibilityTraits = .button
    handle.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(extendAction)))
    let timeColumn = UIStackView(arrangedSubviews: [time, timeLegend])
    timeColumn.axis = .vertical
    timeColumn.spacing = 7
    timeColumn.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleInfoAction)))
    timeColumn.accessibilityCustomActions = [UIAccessibilityCustomAction(name: L("mikshat_toggle_time"), target: self, selector: #selector(accessibleToggleTime))]
    let speedColumn = UIStackView(arrangedSubviews: [speed, speedUnit])
    speedColumn.axis = .vertical; speedColumn.spacing = 7
    speedColumn.translatesAutoresizingMaskIntoConstraints = false
    speedBox.addSubview(speedColumn)
    NSLayoutConstraint.activate([
      speedColumn.topAnchor.constraint(equalTo: speedBox.topAnchor), speedColumn.bottomAnchor.constraint(equalTo: speedBox.bottomAnchor),
      speedColumn.leadingAnchor.constraint(equalTo: speedBox.leadingAnchor), speedColumn.trailingAnchor.constraint(equalTo: speedBox.trailingAnchor),
    ])
    let distanceColumn = UIStackView(arrangedSubviews: [distance, distanceUnit])
    distanceColumn.axis = .vertical; distanceColumn.spacing = 7
    let metrics = UIStackView(arrangedSubviews: [distanceColumn, timeColumn, speedBox])
    metrics.semanticContentAttribute = .forceLeftToRight
    metrics.distribution = .fillEqually
    metrics.spacing = 8
    metrics.heightAnchor.constraint(greaterThanOrEqualToConstant: 102).isActive = true
    for label in [distance, distanceUnit, time, speed, speedUnit] {
      label.textAlignment = .center
      label.numberOfLines = 1
      label.textColor = label === distanceUnit || label === speedUnit ? .gray : .black
    }
    for button in [stop, voice, settings] {
      NSLayoutConstraint.deactivate(button.constraints.filter { $0.firstAttribute == .width })
    }
    let actions = UIStackView(arrangedSubviews: [stop, voice, settings])
    actions.semanticContentAttribute = .forceLeftToRight
    actions.spacing = 14
    actions.translatesAutoresizingMaskIntoConstraints = false
    voice.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    settings.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    voice.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    settings.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    stop.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
    navigationActionsRow = actions
    extended.addSubview(actions)
    NSLayoutConstraint.activate([
      actions.topAnchor.constraint(equalTo: extended.topAnchor, constant: 8), actions.bottomAnchor.constraint(equalTo: extended.bottomAnchor, constant: -8).withPriority(.required - 1),
      actions.leadingAnchor.constraint(equalTo: extended.leadingAnchor), actions.trailingAnchor.constraint(equalTo: extended.trailingAnchor),
      actions.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).withPriority(.required - 1),
    ])
    extended.isHidden = true
    let stack = UIStackView(arrangedSubviews: [handle, metrics, progress, extended])
    stack.axis = .vertical; stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 7), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
    ])
    legacyViews.forEach { $0.isHidden = true }
  }

  @objc private func accessibleToggleTime() -> Bool { toggleInfoAction(); return true }

  @objc private func mikshatPan(_ gesture: UIPanGestureRecognizer) {
    guard gesture.state == .ended else { return }
    let y = gesture.translation(in: self).y
    if abs(y) > 12 { isExtended = y < 0; refreshDiminishTimer() }
  }

  private func configureMetricLabel(_ label: UILabel, font: UIFont) {
    label.font = font
    label.adjustsFontForContentSizeCategory = false
    label.clipsToBounds = true
    label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    label.configureSingleLineAutoScaling()
  }

  private func configureButton(_ button: UIButton) {
    button.imageView?.contentMode = .scaleAspectFit
    button.contentHorizontalAlignment = .fill
    button.contentVerticalAlignment = .fill
    button.contentEdgeInsets = UIEdgeInsets(top: Constants.buttonContentInset,
                                            left: Constants.buttonContentInset,
                                            bottom: Constants.buttonContentInset,
                                            right: Constants.buttonContentInset)
  }

  private func configureStopButton(_ button: UIButton) {
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    button.titleLabel?.numberOfLines = 1
    button.titleLabel?.adjustsFontSizeToFitWidth = true
    button.titleLabel?.minimumScaleFactor = 0.5
    button.setContentCompressionResistancePriority(.required, for: .vertical)
    button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 22, bottom: 10, right: 22)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    updateLegendSize()
    if let navigationInfo {
      onNavigationInfoUpdated(navigationInfo)
    }
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard isVisible, let parent = superview else { return }
    updatePlacement(in: parent)
    updateResponsiveMetrics()
    updateActionsLayout()
    MikshatHomeControls.updateNavigationInformationCard(self, visible: true)
    updateVisibleViewportArea()
  }

  private func updateResponsiveMetrics() {
    let columnWidth = max(1, (bounds.width - 48) / 3)
    let valueLimit = max(24, min(56, columnWidth * 0.65))
    let legendLimit = max(12, min(24, columnWidth * 0.36))
    let metrics = UIFontMetrics.default
    for label in [distanceLabel!, speedLabel!, timeLabel!] {
      label.font = metrics.scaledFont(for: .systemFont(ofSize: 38), maximumPointSize: valueLimit, compatibleWith: traitCollection)
    }
    for label in [distanceLegendLabel!, speedLegendLabel!, timeLegend] {
      label.adjustsFontForContentSizeCategory = false
      label.font = metrics.scaledFont(for: .systemFont(ofSize: 18), maximumPointSize: legendLimit, compatibleWith: traitCollection)
      label.configureSingleLineAutoScaling()
    }
    stopButton.titleLabel?.adjustsFontForContentSizeCategory = false
    stopButton.titleLabel?.font = metrics.scaledFont(for: .systemFont(ofSize: 18), maximumPointSize: 22, compatibleWith: traitCollection)
  }

  private func updateActionsLayout() {
    let narrow = bounds.width < 360
    guard narrow != narrowActions else { return }
    narrowActions = narrow
    let actions = navigationActionsRow!
    if narrow {
      for button in [ttsButton!, settingsButton!] {
        actions.removeArrangedSubview(button)
        button.removeFromSuperview()
      }
      let secondary = UIStackView(arrangedSubviews: [ttsButton!, settingsButton!])
      secondary.semanticContentAttribute = .forceLeftToRight
      secondary.distribution = .fillEqually
      secondary.spacing = 14
      secondaryActionsRow = secondary
      actions.axis = .vertical
      actions.spacing = 8
      actions.addArrangedSubview(secondary)
    } else {
      if let secondary = secondaryActionsRow {
        [ttsButton!, settingsButton!].forEach { secondary.removeArrangedSubview($0); $0.removeFromSuperview() }
        actions.removeArrangedSubview(secondary)
        secondary.removeFromSuperview()
      }
      secondaryActionsRow = nil
      actions.axis = .horizontal
      actions.spacing = 14
      actions.addArrangedSubview(ttsButton)
      actions.addArrangedSubview(settingsButton)
    }
  }

  private func updatePlacement(in parent: UIView) {
    let railWidth = MikshatHomeControls.landscapeRailWidth(in: parent)
    guard placementConstraints.isEmpty || placementSize != parent.bounds.size || placementSafeArea != parent.safeAreaInsets || placementRailWidth != railWidth else { return }
    placementSize = parent.bounds.size
    placementSafeArea = parent.safeAreaInsets
    placementRailWidth = railWidth
    NSLayoutConstraint.deactivate(placementConstraints)
    let safe = parent.safeAreaLayoutGuide
    let landscape = parent.bounds.width > parent.bounds.height
    if landscape {
      let width = min(560, max(180, safe.layoutFrame.width - 2 * (railWidth + 8)))
      placementConstraints = [centerXAnchor.constraint(equalTo: safe.centerXAnchor), centerYAnchor.constraint(equalTo: safe.centerYAnchor), widthAnchor.constraint(equalToConstant: width)]
      layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    } else {
      placementConstraints = [leadingAnchor.constraint(equalTo: safe.leadingAnchor), trailingAnchor.constraint(equalTo: safe.trailingAnchor), bottomAnchor.constraint(equalTo: safe.bottomAnchor)]
      layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }
    NSLayoutConstraint.activate(placementConstraints)
  }

  private func addView() {
    guard superview != ownerView, !ownerView.subviews.contains(self) else { return }
    translatesAutoresizingMaskIntoConstraints = false
    ownerView.addSubview(self)
    updatePlacement(in: ownerView)

    let actions = MikshatNavigationActionsView()
    actions.install(in: ownerView, above: self)
    mikshatActions = actions
    updateVisibleViewportArea()
  }

  private func removeView() {
    MikshatHomeControls.updateNavigationInformationCard(self, visible: false)
    // Cancel diminish timer on remove, otherwise performSelector keeps the view alive ~5s after close, blocking deinit.
    cancelDiminishTimer()
    mikshatActions?.removeFromSuperview()
    mikshatActions = nil
    updateVisibleViewportArea(onClose: true)
    dimBackground.setVisible(false, completion: { [weak self] in
      guard let self, !self.isVisible else { return }
      NSLayoutConstraint.deactivate(self.placementConstraints)
      self.placementConstraints = []
      self.removeFromSuperview()
    })
  }

  private func updateVisibleViewportArea(onClose: Bool = false) {
    let parent = superview ?? ownerView
    let landscape = (parent?.bounds.width ?? 0) > (parent?.bounds.height ?? 0)
    let bottom = max(0, (parent?.bounds.maxY ?? 0) - frame.minY)
    let insets = UIEdgeInsets(top: 0, left: 0, bottom: onClose || landscape ? 0 : bottom, right: 0)
    guard onClose || insets != lastViewportInsets else { return }
    lastViewportInsets = insets
    MapViewController.shared()?.updateVisibleAreaInsets(for: self, insets: insets, updatingViewport: true)
  }

  private func updateLegendSize() {
    distanceLabel.isHidden = false
    distanceLegendLabel.isHidden = false
    speedLabel.isHidden = false
    speedLegendLabel.isHidden = false
    legacyViews.forEach { $0.isHidden = true }
  }

  func setTrackRecordingState(_ state: TrackRecordingState) {
    trackRecordingButton.coloring = state == .active ? .red : .black
  }

  func onNavigationInfoUpdated(_ info: MWMNavigationDashboardEntity) {
    navigationInfo = info
    guard isVisible else { return }
    let routingNumberAttributes: [NSAttributedString.Key: Any] =
      [
        NSAttributedString.Key.foregroundColor: UIColor.black,
        NSAttributedString.Key.font: Constants.metricFont,
      ]
    let routingLegendAttributes: [NSAttributedString.Key: Any] =
      [
        NSAttributedString.Key.foregroundColor: UIColor.gray,
        NSAttributedString.Key.font: Constants.metricLegendFont,
      ]

    timeLegend.text = L(timePageControl.currentPage == 0 ? "mikshat_remaining_time" : "mikshat_arrival")
    timeLabel.textColor = .black
    if timePageControl.currentPage == 0 {
      timeLabel.text = DurationFormatter.routingDurationString(from: TimeInterval(info.timeToTarget))
    } else {
      timeLabel.text = info.arrival
    }

    var distanceWithLegend: NSMutableAttributedString?
    if let targetDistance = info.targetDistance {
      distanceLabel.text = targetDistance
      distanceWithLegend = NSMutableAttributedString(string: targetDistance, attributes: routingNumberAttributes)
    }

    if let targetUnits = info.targetUnits {
      distanceLegendLabel.attributedText = NSAttributedString(string: targetUnits, attributes: [
        .baselineOffset: targetUnits.trimmingCharacters(in: .whitespaces) == "كم" ? 3 : 0,
      ])
      if let distanceWithLegend = distanceWithLegend {
        var distanceUnitAttributes = routingLegendAttributes
        if targetUnits.trimmingCharacters(in: .whitespaces) == "كم" { distanceUnitAttributes[.baselineOffset] = 3 }
        distanceWithLegend.append(NSAttributedString(string: targetUnits, attributes: distanceUnitAttributes))
        distanceWithLegendLabel.attributedText = distanceWithLegend
      }
    }

    var speedMps = 0.0
    if let s = LocationManager.lastLocation()?.speed, s > 0 {
      speedMps = s
    }
    let speedMeasure = Measure(asSpeed: speedMps)
    var speed = speedMeasure.valueAsString

    // @todo Draw speed limit sign similar to the CarPlay implemenation.
    // speedLimitMps >= 0 means known limited speed.
    if info.speedLimitMps >= 0 {
      // A compact separator keeps the speed from overlapping durations of an hour or more.
      let separator = info.timeToTarget < 60 * 60 ? " / " : "/"
      let speedLimitMeasure = Measure(asSpeed: info.speedLimitMps)
      // speedLimitMps == 0 means unlimited speed.
      speed += separator + (info.speedLimitMps == 0 ? "∞" : speedLimitMeasure.valueAsString)
    }

    speedLabel.text = speed
    speedLegendLabel.text = speedMeasure.unit
    let speedWithLegend = NSMutableAttributedString(string: speed, attributes: routingNumberAttributes)
    speedWithLegend.append(NSAttributedString(string: speedMeasure.unit, attributes: routingLegendAttributes))
    speedWithLegendLabel.attributedText = speedWithLegend

    if MWMRouter.isSpeedCamLimitExceeded() {
      speedLabel.textColor = .whitePrimary
      speedBackground.backgroundColor = .buttonRed
    } else {
      let isSpeedLimitExceeded = info.speedLimitMps > 0 && speedMps > info.speedLimitMps
      speedLabel.textColor = isSpeedLimitExceeded ? .buttonRed : .black
      speedBackground.backgroundColor = UIColor.clear
    }
    speedLegendLabel.textColor = speedLabel.textColor
    speedWithLegendLabel.textColor = speedLabel.textColor

    routingProgress.constant = progressView.width * info.progress / 100
  }

  @IBAction
  private func toggleInfoAction() {
    if let navigationInfo = navigationInfo {
      timePageControl.currentPage = (timePageControl.currentPage + 1) % timePageControl.numberOfPages
      onNavigationInfoUpdated(navigationInfo)
    }
    refreshDiminishTimer()
  }

  @IBAction
  private func extendAction() {
    isExtended = !isExtended
    refreshDiminishTimer()
  }

  @IBAction
  private func ttsButtonAction(_: Any) {
    delegate.ttsButtonDidTap()
  }

  @IBAction
  private func settingsButtonAction(_: Any) {
    delegate.settingsButtonDidTap()
  }

  @IBAction
  private func stopRoutingButtonAction(_: Any) {
    delegate.stopRoutingButtonDidTap()
  }

  @IBAction
  private func trackRecordingButtonAction(_: Any) {
    delegate.trackRecordingButtonDidTap()
  }

  private func morphExtendButton() {
    guard let imageView = extendButton.imageView else { return }
    let morphImagesCount = 6
    let startValue = isExtended ? morphImagesCount : 1
    let endValue = isExtended ? 0 : morphImagesCount + 1
    let stepValue = isExtended ? -1 : 1
    var morphImages: [UIImage] = []
    for i in stride(from: startValue, to: endValue, by: stepValue) {
      morphImages.append(UIImage(named: "ic_menu_\(i)")!)
    }
    imageView.animationImages = morphImages
    imageView.animationRepeatCount = 1
    imageView.animationDuration = 0.2
    imageView.image = morphImages.last
    imageView.startAnimating()
    setExtendButtonImage()
  }

  private func setExtendButtonImage() {
    guard let imageView = extendButton.imageView else { return }
    let update: () -> Void = { [weak self] in
      guard let self else { return }
      self.extendButton.setImage(UIImage(resource: self.isExtended ? .icMenuDown : .icMenu), for: .normal)
    }
    if imageView.isAnimating {
      // One completion update, rather than repeatedly rescheduling work on the main queue.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: update)
    } else { update() }
  }

  private func refreshDiminishTimer() {
    cancelDiminishTimer()
    perform(diminishSelector, with: self, afterDelay: 5)
  }

  private func cancelDiminishTimer() {
    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: diminishSelector, object: self)
  }

  @objc
  private func diminish() {
    isExtended = false
  }

  override func applyTheme() {
    super.applyTheme()
    onTTSStatusUpdated()
    setTrackRecordingState(TrackRecordingManager.shared.recordingState)
  }

  override var sideButtonsAreaAffectDirections: MWMAvailableAreaAffectDirections {
    .bottom
  }

  override var widgetsAreaAffectDirections: MWMAvailableAreaAffectDirections {
    alternative(iPhone: .bottom, iPad: [])
  }

  override var trackRecordingButtonAreaAffectDirections: MWMAvailableAreaAffectDirections {
    .bottom
  }
}

extension NavigationControlView: MWMTextToSpeechObserver {
  func onTTSStatusUpdated() {
    guard MWMRouter.isRoutingActive() else { return }
    ttsButton.isHidden = !MWMTextToSpeech.isTTSEnabled()
    if !ttsButton.isHidden {
      ttsButton.isSelected = MWMTextToSpeech.tts().active
    }
    refreshDiminishTimer()
  }
}
