import UIKit
import CoreLocation

enum MikshatNavigationCoordinator {
  static var compassSelected = false
  static private(set) var directView: MikshatDirectGuidanceView?
  static var isDirectActive: Bool { directView != nil }

  static func startCustomNavigation() -> Bool {
    guard let fix = LocationManager.lastLocation(), fix.horizontalAccuracy >= 0,
          abs(fix.timestamp.timeIntervalSinceNow) < 15, let point = MWMRouter.finishPoint(),
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
    stopDirectNavigation(stopRouter: false)
    let hud = MikshatDirectGuidanceView(target: destination, name: point.title)
    directView = hud
    hud.translatesAutoresizingMaskIntoConstraints = false
    map.view.addSubview(hud)
    NSLayoutConstraint.activate([
      hud.leadingAnchor.constraint(equalTo: map.view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
      hud.trailingAnchor.constraint(equalTo: map.view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      hud.bottomAnchor.constraint(equalTo: map.view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
    ])
    LocationManager.setMyPositionMode(.follow)
    MapsAppDelegate.theApp().disableStandby()
    hud.start()
    return true
  }

  static func stopDirectNavigation(stopRouter: Bool = true) {
    if let hud = directView {
      hud.stop()
      hud.removeFromSuperview()
      directView = nil
      MapsAppDelegate.theApp().enableStandby()
      if stopRouter { MWMRouter.stopRouting() }
    }
  }
}

final class MikshatDirectGuidanceView: UIStackView, MWMLocationObserver {
  private let target: CLLocationCoordinate2D
  private let values = MikshatStyle.label(size: 21, color: MikshatStyle.green)
  private let times = MikshatStyle.label(size: 15, color: MikshatStyle.green)
  private var estimate = MikshatTravelEstimate()
  private var timer: Timer?
  private var lastRebuild: Date = .distantPast
  private var lastPosition: CLLocation?

  init(target: CLLocationCoordinate2D, name: String) {
    self.target = target
    super.init(frame: .zero)
    axis = .vertical
    spacing = 10
    backgroundColor = MikshatStyle.cream
    layer.cornerRadius = 24
    isLayoutMarginsRelativeArrangement = true
    layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 14, right: 16)
    let close = MikshatStyle.button(L("mikshat_stop"), symbol: "xmark.circle") { MikshatNavigationCoordinator.stopDirectNavigation() }
    let title = MikshatStyle.label(name, size: 20, color: MikshatStyle.green)
    let header = UIStackView(arrangedSubviews: [title, close])
    header.spacing = 12
    close.widthAnchor.constraint(equalToConstant: 52).isActive = true
    addArrangedSubview(header)
    addArrangedSubview(values)
    addArrangedSubview(times)
    addArrangedSubview(MikshatStyle.label(L("mikshat_direct_notice"), size: 12, color: .secondaryLabel))
  }
  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func start() {
    LocationManager.add(observer: self)
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    refresh()
  }
  func stop() { timer?.invalidate(); timer = nil; LocationManager.remove(observer: self) }
  func onLocationUpdate(_ location: CLLocation) { refresh() }
  private func refresh() {
    guard let endpoint = MWMRouter.finishPoint(), MWMRouter.type() == .ruler,
          abs(endpoint.latitude - target.latitude) < 0.000001,
          abs(endpoint.longitude - target.longitude) < 0.000001 else {
      MikshatNavigationCoordinator.stopDirectNavigation(stopRouter: false)
      return
    }
    guard let fix = LocationManager.lastLocation(), fix.horizontalAccuracy >= 0,
          abs(fix.timestamp.timeIntervalSinceNow) < 15 else {
      values.text = L("mikshat_location_unavailable"); times.text = "—"; return
    }
    let distance = fix.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
    let speed = fix.speed >= 0 ? String(Int((fix.speed * 3.6).rounded())) : "—"
    values.text = DistanceFormatter.distanceString(fromMeters: distance) + "   •   " + speed + " " + L("mikshat_kmh")
    if let remaining = estimate.update(distance: distance, speed: fix.speed, timestamp: fix.timestamp.timeIntervalSince1970, now: Date().timeIntervalSince1970) {
      let formatter = DateFormatter(); formatter.timeStyle = .short
      times.text = DurationFormatter.routingDurationString(from: remaining) + "   •   " + formatter.string(from: Date().addingTimeInterval(remaining))
    } else { times.text = L("mikshat_waiting") }
    // Keep the native ruler line tied to the moving start; throttle expensive route rebuilds.
    if Date().timeIntervalSince(lastRebuild) > 3,
       lastPosition == nil || fix.distance(from: lastPosition!) >= 5,
       let start = MWMRoutePoint(lastLocationAndType: .start, intermediateIndex: 0) {
      lastRebuild = Date()
      lastPosition = fix
      MWMRouter.addPointAndRebuild(start)
    }
  }
}
