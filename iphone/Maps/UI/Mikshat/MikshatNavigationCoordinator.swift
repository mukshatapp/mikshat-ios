import UIKit
import CoreLocation

enum MikshatNavigationCoordinator {
  static var compassSelected = false
  static private(set) var directView: MikshatDirectGuidanceView?
  private static var actions: MikshatNavigationActionsView?
  private static var directDestination: (coordinate: CLLocationCoordinate2D, title: String?)?
  static var isDirectActive: Bool { directView != nil }
  static let visibilityChanged = Notification.Name("MikshatDirectVisibilityChanged")

  static func startCustomNavigation() -> Bool {
    guard !isDirectActive else { return false }
    LocationManager.start()
    guard let point = MWMRouter.finishPoint(), let map = MapViewController.shared() else {
      Toast.show(withText: L("mikshat_location_unavailable"))
      return false
    }
    let destination = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    if compassSelected {
      let title = point.title
      let controller = MikshatCompassViewController(target: destination, name: title, onClose: {
        restoreDestinationSelection(coordinate: destination, title: title)
      })
      controller.modalPresentationStyle = .overFullScreen
      map.present(controller, animated: true)
      return true
    }
    guard let origin = MikshatHeading.navigationLocation else {
      Toast.show(withText: L("mikshat_location_unavailable"))
      return false
    }
    let hud = MikshatDirectGuidanceView(target: destination, origin: origin)
    directDestination = (destination, point.title)
    directView = hud
    hud.translatesAutoresizingMaskIntoConstraints = false
    map.view.insertSubview(hud, belowSubview: map.placePageContainer)
    hud.installPlacement(in: map.view)
    let tools = MikshatNavigationActionsView()
    tools.install(in: map.view, above: hud)
    actions = tools
    MWMRouter.beginMikshatDirect(from: origin.coordinate, to: destination)
    NotificationCenter.default.post(name: visibilityChanged, object: nil)
    MapsAppDelegate.theApp().disableStandby()
    hud.start()
    return true
  }

  static func stopDirectNavigation(stopRouter: Bool = true) {
    guard let hud = directView else { return }
    let destination = directDestination
    directDestination = nil
    hud.stop()
    hud.removeFromSuperview()
    actions?.removeFromSuperview()
    actions = nil
    directView = nil
    MWMRouter.endMikshatDirect()
    NotificationCenter.default.post(name: visibilityChanged, object: nil)
    MapsAppDelegate.theApp().enableStandby()
    if stopRouter {
      MWMRouter.stopRouting()
      if let destination {
        restoreDestinationSelection(coordinate: destination.coordinate, title: destination.title)
      }
    } else if let destination, !MWMRouter.isRoutingActive(), MWMRouter.pointsCount() == 0 {
      restoreDestinationSelection(coordinate: destination.coordinate, title: destination.title)
    }
  }

  static func restoreDestinationSelection(coordinate: CLLocationCoordinate2D, title: String?) {
    guard CLLocationCoordinate2DIsValid(coordinate) else { return }
    // Capture callers' destination before clearing routing; current GPS is never a fallback.
    stopDirectNavigation(stopRouter: false)
    if MWMRouter.isRoutingActive() || MWMRouter.pointsCount() > 0 { MWMRouter.stopRouting() }
    DispatchQueue.main.async {
      // A newly started route takes precedence over a dismissal still finishing its animation.
      guard !MWMRouter.isRoutingActive(), MWMRouter.pointsCount() == 0 else { return }
      MWMRouter.restoreMikshatDestination(coordinate, title: title)
    }
  }
}

final class MikshatNavigationActionsView: UIStackView {
  private let recording = UIButton(type: .system)
  private var leftConstraint: NSLayoutConstraint?
  private var compactLayout: Bool?
  private var buttonSizes: [NSLayoutConstraint] = []
  private var bottomConstraint: NSLayoutConstraint?
  private var landscapeBottomConstraint: NSLayoutConstraint?

  init() {
    super.init(frame: .zero)
    axis = .vertical
    spacing = 9
    func button(_ key: String, symbol: String, action: @escaping () -> Void) -> UIButton {
      let button = UIButton(type: .system)
      button.setImage(MikshatSymbols.image(named: symbol), for: .normal)
      button.tintColor = MikshatStyle.green
      button.backgroundColor = .white
      button.layer.cornerRadius = 26
      button.accessibilityLabel = L(key)
      let size = button.heightAnchor.constraint(equalToConstant: 52)
      buttonSizes.append(size)
      size.isActive = true
      button.widthAnchor.constraint(equalToConstant: 52).isActive = true
      button.addAction(UIAction { _ in action() }, for: .touchUpInside)
      return button
    }
    addArrangedSubview(button("search", symbol: "magnifyingglass") {
      guard let manager = MapViewController.shared()?.searchManager else { return }
      manager.startSearching(isRouting: MWMRouter.isRoutingActive())
    })
    addArrangedSubview(button("bookmarks", symbol: "bookmark") {
      MapViewController.shared()?.bookmarksCoordinator.open()
    })
    recording.setImage(MikshatSymbols.image(named: "record.circle"), for: .normal)
    recording.backgroundColor = .white
    recording.layer.cornerRadius = 26
    recording.accessibilityLabel = L("mikshat_record_track")
    recording.widthAnchor.constraint(equalToConstant: 52).isActive = true
    let size = recording.heightAnchor.constraint(equalToConstant: 52)
    buttonSizes.append(size)
    size.isActive = true
    recording.addAction(UIAction { _ in
      let recorder = TrackRecordingManager.shared
      if recorder.recordingState == .active { recorder.stopAndSave() }
      else {
        recorder.start { result in
          if case .failure = result { Toast.show(withText: L("mikshat_location_unavailable")) }
        }
      }
    }, for: .touchUpInside)
    addArrangedSubview(recording)
    updateRecording(TrackRecordingManager.shared.recordingState)
    TrackRecordingManager.shared.addObserver(self) { [weak self] state, _, _ in self?.updateRecording(state) }
  }
  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit { TrackRecordingManager.shared.removeObserver(self) }

  private func updateRecording(_ state: TrackRecordingState) {
    recording.tintColor = state == .active ? .systemRed : .black
    recording.accessibilityValue = L(state == .active ? "on" : "off")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let container = superview else { return }
    let compact = container.bounds.width > container.bounds.height
    if compactLayout != compact {
      compactLayout = compact
      axis = compact ? .horizontal : .vertical
      spacing = compact ? 6 : 9
      buttonSizes.forEach { $0.constant = compact ? 44 : 52 }
      bottomConstraint?.isActive = !compact
      landscapeBottomConstraint?.isActive = compact
    }
    let original = CGRect(x: container.safeAreaInsets.left + 12, y: frame.minY, width: frame.width, height: frame.height)
    let globe = MikshatSatelliteController.shared.buttonFrame(in: container)
    let offset = globe.map { original.intersects($0.insetBy(dx: -6, dy: -6)) ? $0.maxX - container.safeAreaInsets.left + 10 : 12 } ?? 12
    if leftConstraint?.constant != offset { leftConstraint?.constant = offset }
  }

  func install(in container: UIView, above card: UIView) {
    translatesAutoresizingMaskIntoConstraints = false
    // Keep map tools below the search and place-card containers.
    if let map = MapViewController.shared(), container === map.view {
      container.insertSubview(self, belowSubview: map.placePageContainer)
    } else { container.addSubview(self) }
    leftConstraint = leftAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leftAnchor, constant: 12)
    bottomConstraint = bottomAnchor.constraint(equalTo: card.topAnchor, constant: -12)
    landscapeBottomConstraint = bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -12)
    NSLayoutConstraint.activate([
      leftConstraint!,
      bottomConstraint!,
    ])
  }
}

final class MikshatDirectGuidanceView: UIStackView, MWMLocationObserver {
  private let target: CLLocationCoordinate2D
  private let distanceValue = MikshatStyle.label("—", size: 38, color: .black)
  private let distanceUnit = MikshatStyle.label(size: 18, color: .gray)
  private let speedValue = MikshatStyle.label("—", size: 38, color: .black)
  private let timeValue = MikshatStyle.label("—", size: 34, color: .systemBlue)
  private let timeLegend = MikshatStyle.label(L("mikshat_waiting"), size: 17, color: .gray)
  private let stopButton = UIButton(type: .system)
  private var estimate = MikshatTravelEstimate()
  private var timer: Timer?
  private var lastRebuild: Date = .distantPast
  private var lastPosition: CLLocation?
  private var lastKnownPosition: CLLocation?
  private var lastRefresh: TimeInterval = 0
  private var lastInsets = UIEdgeInsets.zero
  private var placementConstraints: [NSLayoutConstraint] = []
  private var placementSize = CGSize.zero
  private var placementSafeArea = UIEdgeInsets.zero
  private var placementRailWidth: CGFloat = 0
  private var metricLegends: [UILabel] = []

  init(target: CLLocationCoordinate2D, origin: CLLocation) {
    self.target = target
    lastKnownPosition = origin
    super.init(frame: .zero)
    accessibilityIdentifier = "navigation.directInfoCard"
    speedValue.accessibilityIdentifier = "navigation.direct.speedValue"
    distanceValue.accessibilityIdentifier = "navigation.direct.distanceValue"
    timeValue.accessibilityIdentifier = "navigation.direct.timeValue"
    axis = .vertical
    spacing = 12
    backgroundColor = .white
    layer.cornerRadius = 24
    layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    isLayoutMarginsRelativeArrangement = true
    layoutMargins = UIEdgeInsets(top: 7, left: 16, bottom: 12, right: 16)
    let grabber = UIView()
    grabber.backgroundColor = .lightGray
    grabber.layer.cornerRadius = 3
    let handle = UIView()
    grabber.translatesAutoresizingMaskIntoConstraints = false
    handle.addSubview(grabber)
    NSLayoutConstraint.activate([
      handle.heightAnchor.constraint(equalToConstant: 8),
      grabber.centerXAnchor.constraint(equalTo: handle.centerXAnchor),
      grabber.centerYAnchor.constraint(equalTo: handle.centerYAnchor),
      grabber.widthAnchor.constraint(equalToConstant: 38), grabber.heightAnchor.constraint(equalToConstant: 5),
    ])
    addArrangedSubview(handle)
    func column(_ value: UILabel, _ legend: UILabel) -> UIView {
      let stack = UIStackView(arrangedSubviews: [value, legend])
      stack.axis = .vertical
      stack.spacing = 7
      value.numberOfLines = 1
      value.adjustsFontSizeToFitWidth = true
      value.minimumScaleFactor = 0.5
      return stack
    }
    let speedUnit = MikshatStyle.label(L("mikshat_kmh"), size: 18, color: .gray)
    speedUnit.accessibilityIdentifier = "navigation.direct.speedUnit"
    metricLegends = [distanceUnit, timeLegend, speedUnit]
    let row = UIStackView(arrangedSubviews: [column(distanceValue, distanceUnit), column(timeValue, timeLegend), column(speedValue, speedUnit)])
    row.semanticContentAttribute = .forceLeftToRight
    row.distribution = .fillEqually
    row.spacing = 8
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 102).isActive = true
    addArrangedSubview(row)
    var config = UIButton.Configuration.filled()
    config.title = L("mikshat_stop_navigation")
    config.baseBackgroundColor = .systemRed
    config.baseForegroundColor = .white
    config.cornerStyle = .medium
    stopButton.configuration = config
    stopButton.titleLabel?.numberOfLines = 1
    stopButton.titleLabel?.adjustsFontSizeToFitWidth = true
    stopButton.titleLabel?.minimumScaleFactor = 0.5
    stopButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).withPriority(.required - 1).isActive = true
    stopButton.addAction(UIAction { _ in MikshatNavigationCoordinator.stopDirectNavigation() }, for: .touchUpInside)
    stopButton.isHidden = true
    addArrangedSubview(stopButton)
    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
    handle.isAccessibilityElement = true
    handle.accessibilityIdentifier = "navigation.direct.expand"
    handle.accessibilityLabel = L("mikshat_show_stop")
    handle.accessibilityTraits = .button
    handle.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleExpanded)))
    stopButton.accessibilityIdentifier = "navigation.direct.stop"
    accessibilityCustomActions = [UIAccessibilityCustomAction(name: L("mikshat_stop_navigation"), target: self, selector: #selector(accessibleStop))]
  }
  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc private func accessibleStop() -> Bool { MikshatNavigationCoordinator.stopDirectNavigation(); return true }
  @objc private func panned(_ gesture: UIPanGestureRecognizer) {
    guard gesture.state == .ended else { return }
    let movement = gesture.translation(in: self).y
    if abs(movement) > 12 { setExpanded(movement < 0) }
  }
  @objc private func toggleExpanded() { setExpanded(stopButton.isHidden) }
  private func setExpanded(_ expanded: Bool) {
    stopButton.isHidden = !expanded
    UIView.animate(withDuration: 0.2) { self.superview?.layoutIfNeeded() }
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    guard let parent = superview else { return }
    installPlacement(in: parent)
    MikshatHomeControls.updateNavigationInformationCard(self, visible: true)
    let columnWidth = max(1, (bounds.width - 48) / 3)
    let valueLimit = max(24, min(56, columnWidth * 0.65))
    let legendLimit = max(12, min(24, columnWidth * 0.36))
    for label in [distanceValue, speedValue, timeValue] {
      label.adjustsFontForContentSizeCategory = false
      label.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 38), maximumPointSize: valueLimit, compatibleWith: traitCollection)
    }
    for label in metricLegends {
      label.adjustsFontForContentSizeCategory = false
      label.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 18), maximumPointSize: legendLimit, compatibleWith: traitCollection)
      label.configureSingleLineAutoScaling()
    }
    let landscape = parent.bounds.width > parent.bounds.height
    let insets = UIEdgeInsets(top: 0, left: 0, bottom: landscape ? 0 : parent.bounds.maxY - frame.minY, right: 0)
    guard bounds.height > 0, insets != lastInsets else { return }
    lastInsets = insets
    MapViewController.shared()?.updateVisibleAreaInsets(for: self, insets: insets, updatingViewport: true)
  }

  func installPlacement(in parent: UIView) {
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
  func start() {
    timer?.invalidate()
    LocationManager.add(observer: self)
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    refresh()
  }
  func stop() {
    MikshatHomeControls.updateNavigationInformationCard(self, visible: false)
    timer?.invalidate()
    timer = nil
    LocationManager.remove(observer: self)
    MapViewController.shared()?.updateVisibleAreaInsets(for: self, insets: .zero, updatingViewport: true)
  }
  deinit { timer?.invalidate() }
  func onLocationUpdate(_ location: CLLocation) { refresh() }
  private func refresh() {
    guard MWMRouter.isMikshatDirectActive(), let endpoint = MWMRouter.finishPoint(), MWMRouter.type() == .ruler,
          abs(endpoint.latitude - target.latitude) < 0.000001,
          abs(endpoint.longitude - target.longitude) < 0.000001 else {
      MikshatNavigationCoordinator.stopDirectNavigation(stopRouter: false)
      return
    }
    let now = Date().timeIntervalSince1970
    guard now - lastRefresh >= 0.5 else { return }
    lastRefresh = now
    let arrow = MikshatHeading.navigationLocation
    if let arrow { lastKnownPosition = arrow }
    guard let fix = arrow ?? lastKnownPosition else {
      distanceValue.text = "—"; speedValue.text = "—"; timeValue.text = "—"; timeLegend.text = L("mikshat_location_unavailable"); return
    }
    let fresh = arrow != nil && MikshatHeading.currentLocation != nil && MikshatHeading.isFresh(fix)
    let distance = fix.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
    let parts = MikshatNavigationMath.distanceParts(DistanceFormatter.distanceString(fromMeters: distance))
    distanceValue.text = parts.value
    distanceUnit.text = parts.unit
    let kph = (fix.speed * 3.6).rounded()
    speedValue.text = fresh && kph.isFinite && kph >= 0 && kph < Double(Int.max) ? String(Int(kph)) : "—"
    if !fresh { estimate = MikshatTravelEstimate() }
    let remaining = fresh ? estimate.update(distance: distance, speed: fix.speed, timestamp: fix.timestamp.timeIntervalSince1970, now: now) : nil
    if let remaining {
      timeValue.text = DurationFormatter.routingDurationString(from: remaining)
      timeLegend.text = L("mikshat_remaining_time")
    } else { timeValue.text = "—"; timeLegend.text = L(fresh ? "mikshat_waiting" : "mikshat_cached_location") }
    // Keep the existing purple line tied to movement. The independent blue baseline is never rebuilt here.
    if fresh, Date().timeIntervalSince(lastRebuild) > 3,
       lastPosition == nil || fix.distance(from: lastPosition!) >= 5,
       let start = MWMRouter.mikshatUserPosition() {
      lastRebuild = Date()
      lastPosition = fix
      MWMRouter.addPointAndRebuild(start)
    }
  }
}
