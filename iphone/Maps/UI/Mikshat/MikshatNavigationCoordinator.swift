import UIKit
import CoreLocation

enum MikshatNavigationCoordinator {
  static var compassSelected = false
  static private(set) var directView: MikshatDirectGuidanceView?
  private static var actions: MikshatNavigationActionsView?
  static var isDirectActive: Bool { directView != nil }
  static let visibilityChanged = Notification.Name("MikshatDirectVisibilityChanged")

  static func startCustomNavigation() -> Bool {
    guard !isDirectActive, let fix = MikshatHeading.currentLocation, let point = MWMRouter.finishPoint(),
          let map = MapViewController.shared() else {
      Toast.show(withText: L("mikshat_location_unavailable"))
      return false
    }
    let destination = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    if compassSelected {
      let controller = MikshatCompassViewController(target: destination, name: point.title)
      controller.modalPresentationStyle = .fullScreen
      map.present(controller, animated: true)
      return true
    }
    let hud = MikshatDirectGuidanceView(target: destination)
    directView = hud
    hud.translatesAutoresizingMaskIntoConstraints = false
    map.view.insertSubview(hud, belowSubview: map.placePageContainer)
    NSLayoutConstraint.activate([
      hud.leftAnchor.constraint(equalTo: map.view.safeAreaLayoutGuide.leftAnchor),
      hud.rightAnchor.constraint(equalTo: map.view.safeAreaLayoutGuide.rightAnchor),
      hud.bottomAnchor.constraint(equalTo: map.view.safeAreaLayoutGuide.bottomAnchor),
    ])
    let tools = MikshatNavigationActionsView()
    tools.install(in: map.view, above: hud)
    actions = tools
    MWMRouter.beginMikshatDirect(from: fix.coordinate, to: destination)
    NotificationCenter.default.post(name: visibilityChanged, object: nil)
    LocationManager.setMyPositionMode(.follow)
    MapsAppDelegate.theApp().disableStandby()
    hud.start()
    return true
  }

  static func stopDirectNavigation(stopRouter: Bool = true) {
    guard let hud = directView else { return }
    hud.stop()
    hud.removeFromSuperview()
    actions?.removeFromSuperview()
    actions = nil
    directView = nil
    MWMRouter.endMikshatDirect()
    NotificationCenter.default.post(name: visibilityChanged, object: nil)
    MapsAppDelegate.theApp().enableStandby()
    if stopRouter { MWMRouter.stopRouting() }
  }
}

final class MikshatNavigationActionsView: UIStackView {
  private let recording = UIButton(type: .system)

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
      button.heightAnchor.constraint(equalToConstant: 52).isActive = true
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
    recording.heightAnchor.constraint(equalToConstant: 52).isActive = true
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

  func install(in container: UIView, above card: UIView) {
    translatesAutoresizingMaskIntoConstraints = false
    // Keep map tools below the search and place-card containers.
    if let map = MapViewController.shared(), container === map.view {
      container.insertSubview(self, belowSubview: map.placePageContainer)
    } else { container.addSubview(self) }
    NSLayoutConstraint.activate([
      leftAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leftAnchor, constant: 12),
      bottomAnchor.constraint(equalTo: card.topAnchor, constant: -12),
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
  private var lastRefresh: TimeInterval = 0
  private var lastHeight: CGFloat = 0

  init(target: CLLocationCoordinate2D) {
    self.target = target
    super.init(frame: .zero)
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
    let row = UIStackView(arrangedSubviews: [column(distanceValue, distanceUnit), column(timeValue, timeLegend), column(speedValue, MikshatStyle.label(L("mikshat_kmh"), size: 18, color: .gray))])
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
    stopButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).withPriority(.required - 1).isActive = true
    stopButton.addAction(UIAction { _ in MikshatNavigationCoordinator.stopDirectNavigation() }, for: .touchUpInside)
    stopButton.isHidden = true
    addArrangedSubview(stopButton)
    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
    handle.isAccessibilityElement = true
    handle.accessibilityLabel = L("mikshat_show_stop")
    handle.accessibilityTraits = .button
    handle.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleExpanded)))
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
    guard bounds.height > 0, bounds.height != lastHeight else { return }
    lastHeight = bounds.height
    MapViewController.shared()?.updateVisibleAreaInsets(for: self, insets: UIEdgeInsets(top: 0, left: 0, bottom: bounds.height, right: 0), updatingViewport: true)
  }
  func start() {
    timer?.invalidate()
    LocationManager.add(observer: self)
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    refresh()
  }
  func stop() {
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
    guard let fix = MikshatHeading.currentLocation else {
      distanceValue.text = "—"; speedValue.text = "—"; timeValue.text = "—"; timeLegend.text = L("mikshat_location_unavailable"); return
    }
    let distance = fix.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
    let parts = MikshatNavigationMath.distanceParts(DistanceFormatter.distanceString(fromMeters: distance))
    distanceValue.text = parts.value
    distanceUnit.text = parts.unit
    speedValue.text = fix.speed >= 0 ? String(Int((fix.speed * 3.6).rounded())) : "—"
    if let remaining = estimate.update(distance: distance, speed: fix.speed, timestamp: fix.timestamp.timeIntervalSince1970, now: now) {
      timeValue.text = DurationFormatter.routingDurationString(from: remaining)
      timeLegend.text = L("mikshat_remaining_time")
    } else { timeValue.text = "—"; timeLegend.text = L("mikshat_waiting") }
    // Keep the existing purple line tied to movement. The independent blue baseline is never rebuilt here.
    if Date().timeIntervalSince(lastRebuild) > 3,
       lastPosition == nil || fix.distance(from: lastPosition!) >= 5,
       let start = MWMRoutePoint(lastLocationAndType: .start, intermediateIndex: 0) {
      lastRebuild = Date()
      lastPosition = fix
      MWMRouter.addPointAndRebuild(start)
    }
  }
}
