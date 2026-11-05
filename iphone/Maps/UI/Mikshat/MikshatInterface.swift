import UIKit
import CoreLocation

// Shared visual language for the phone UI; all distances are computed from live locations.
enum MikshatStyle {
  static let green = UIColor(red: 22 / 255, green: 78 / 255, blue: 63 / 255, alpha: 1)
  static let cream = UIColor(red: 251 / 255, green: 250 / 255, blue: 243 / 255, alpha: 1)
  static let gold = UIColor(red: 209 / 255, green: 181 / 255, blue: 105 / 255, alpha: 1)
  static let cyan = UIColor(red: 30 / 255, green: 194 / 255, blue: 208 / 255, alpha: 1)
  static let night = UIColor(red: 3 / 255, green: 24 / 255, blue: 34 / 255, alpha: 1)

  static func label(_ text: String = "", size: CGFloat = 18, color: UIColor = .label) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: size))
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 0
    label.textAlignment = .center
    label.textColor = color
    return label
  }

  static func button(_ title: String, symbol: String, action: @escaping () -> Void) -> UIButton {
    let button = UIButton(type: .system)
    var config = UIButton.Configuration.plain()
    config.title = title
    config.image = MikshatSymbols.image(named: symbol)
    config.imagePlacement = .top
    config.imagePadding = 7
    config.baseForegroundColor = green
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 25, weight: .regular)
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var result = incoming
      result.font = UIFont.preferredFont(forTextStyle: .caption1)
      return result
    }
    button.configuration = config
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    button.accessibilityLabel = title
    return button
  }
}

final class MikshatKaabaView: UIView {
  override func draw(_ rect: CGRect) {
    let unit = min(rect.width, rect.height)
    let box = CGRect(x: (rect.width - unit * 0.65) / 2, y: unit * 0.12, width: unit * 0.65, height: unit * 0.75)
    UIColor(red: 0.89, green: 0.87, blue: 0.73, alpha: 1).setFill()
    UIBezierPath(rect: box).fill()
    MikshatStyle.gold.setFill()
    UIBezierPath(rect: CGRect(x: box.minX, y: box.minY + unit * 0.12, width: box.width, height: unit * 0.09)).fill()
    MikshatStyle.green.setFill()
    UIBezierPath(rect: CGRect(x: box.midX + unit * 0.08, y: box.maxY - unit * 0.29, width: unit * 0.13, height: unit * 0.29)).fill()
  }
}

@objc(MikshatHomeControls)
final class MikshatHomeControls: UIStackView, MWMLocationObserver {
  private let speed = MikshatStyle.label("0", size: 32, color: MikshatStyle.green)
  private let units = MikshatStyle.label(L("mikshat_kmh"), size: 17, color: MikshatStyle.green)
  private var widthConstraint: NSLayoutConstraint?
  private var topConstraint: NSLayoutConstraint?
  private var qiblaHeightConstraint: NSLayoutConstraint?
  private var lastLandscape: Bool?
  private var timer: Timer?

  @objc(installInView:)
  static func install(in view: UIView) {
    let controls = MikshatHomeControls()
    controls.axis = .vertical
    controls.spacing = 10
    controls.translatesAutoresizingMaskIntoConstraints = false
    let speedCard = UIStackView(arrangedSubviews: [controls.speed, controls.units])
    speedCard.axis = .vertical
    speedCard.alignment = .center
    speedCard.backgroundColor = .white
    speedCard.layer.cornerRadius = 20
    speedCard.isLayoutMarginsRelativeArrangement = true
    speedCard.layoutMargins = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
    let qibla = UIButton(type: .custom)
    qibla.backgroundColor = .white
    qibla.layer.cornerRadius = 20
    qibla.accessibilityLabel = L("mikshat_qibla")
    qibla.addAction(UIAction { _ in
      guard let map = MapViewController.shared() else { return }
      let controller = MikshatCompassViewController(target: nil, name: L("mikshat_qibla"))
      controller.modalPresentationStyle = .fullScreen
      map.present(controller, animated: true)
    }, for: .touchUpInside)
    let kaaba = MikshatKaabaView()
    kaaba.backgroundColor = .clear
    kaaba.isUserInteractionEnabled = false
    kaaba.translatesAutoresizingMaskIntoConstraints = false
    qibla.addSubview(kaaba)
    controls.addArrangedSubview(speedCard)
    controls.addArrangedSubview(qibla)
    view.addSubview(controls)
    controls.widthConstraint = controls.widthAnchor.constraint(equalToConstant: 68)
    controls.topConstraint = controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 64)
    controls.qiblaHeightConstraint = qibla.heightAnchor.constraint(equalToConstant: 64)
    NSLayoutConstraint.activate([
      controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
      controls.topConstraint!, controls.widthConstraint!, controls.qiblaHeightConstraint!,
      kaaba.centerXAnchor.constraint(equalTo: qibla.centerXAnchor), kaaba.centerYAnchor.constraint(equalTo: qibla.centerYAnchor),
      kaaba.widthAnchor.constraint(equalToConstant: 48), kaaba.heightAnchor.constraint(equalTo: kaaba.widthAnchor),
    ])
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let parent = superview else { return }
    let landscape = parent.bounds.width > parent.bounds.height
    guard landscape != lastLandscape else { return }
    lastLandscape = landscape
    axis = landscape ? .horizontal : .vertical
    distribution = landscape ? .fillEqually : .fill
    widthConstraint?.constant = landscape ? 146 : 68
    topConstraint?.constant = landscape ? 4 : 64
    qiblaHeightConstraint?.constant = landscape ? 44 : 64
    units.isHidden = landscape
    speed.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: landscape ? 24 : 32))
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    timer?.invalidate()
    if window != nil {
      LocationManager.add(observer: self)
      timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
      refresh()
    } else { LocationManager.remove(observer: self) }
  }
  func onLocationUpdate(_ location: CLLocation) { refresh() }
  private func refresh() {
    guard let fix = LocationManager.lastLocation(), fix.horizontalAccuracy >= 0,
          abs(fix.timestamp.timeIntervalSinceNow) < 15, fix.speed >= 0 else { speed.text = "—"; return }
    speed.text = String(Int((fix.speed * 3.6).rounded()))
  }
}

final class MikshatCompassDial: UIView {
  var heading: Double = 0 { didSet { setNeedsDisplay() } }
  var bearing: Double? { didSet { setNeedsDisplay() } }
  var qibla = false

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2 - 12
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    MikshatStyle.gold.setStroke()
    let circle = UIBezierPath(arcCenter: .zero, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
    circle.lineWidth = 2
    circle.stroke()
    for degree in stride(from: 0, to: 360, by: 5) {
      let angle = CGFloat((Double(degree) - heading - 90) * .pi / 180)
      let major = degree % 30 == 0
      let inner = radius - (major ? 15 : 7)
      let tick = UIBezierPath()
      tick.move(to: CGPoint(x: cos(angle) * inner, y: sin(angle) * inner))
      tick.addLine(to: CGPoint(x: cos(angle) * (radius - 4), y: sin(angle) * (radius - 4)))
      tick.lineWidth = major ? 2 : 1
      tick.stroke()
      if major {
        let direction = [0: "mikshat_north", 90: "mikshat_east", 180: "mikshat_south", 270: "mikshat_west"][degree]
        let text = qibla ? direction.map { L($0) } : String(degree) + (direction.map { "\n" + L($0) } ?? "")
        if let text {
          let paragraph = NSMutableParagraphStyle()
          paragraph.alignment = .center
          let position = CGPoint(x: cos(angle) * (radius - 38), y: sin(angle) * (radius - 38))
          (text as NSString).draw(in: CGRect(x: position.x - 30, y: position.y - 20, width: 60, height: 45),
                                 withAttributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: MikshatStyle.gold, .paragraphStyle: paragraph])
        }
      }
    }
    if !qibla {
      let star = UIBezierPath()
      for index in 0..<16 {
        let angle = CGFloat(index) * .pi / 8 - .pi / 2
        let length = radius * (index % 2 == 0 ? 0.5 : 0.08)
        let point = CGPoint(x: cos(angle) * length, y: sin(angle) * length)
        if index == 0 { star.move(to: point) } else { star.addLine(to: point) }
      }
      star.close()
      UIColor(red: 0.12, green: 0.25, blue: 0.28, alpha: 1).setFill()
      star.fill()
      let marker = UIBezierPath()
      marker.move(to: CGPoint(x: -7, y: -radius - 4))
      marker.addLine(to: CGPoint(x: 7, y: -radius - 4))
      marker.addLine(to: CGPoint(x: 0, y: -radius + 14))
      marker.close()
      MikshatStyle.gold.setFill()
      marker.fill()
    }
    if let bearing {
      context.rotate(by: CGFloat((bearing - heading) * .pi / 180))
      let arrow = UIBezierPath()
      arrow.move(to: CGPoint(x: 0, y: -radius * 0.65))
      arrow.addLine(to: CGPoint(x: -radius * 0.15, y: -radius * 0.33))
      arrow.addLine(to: CGPoint(x: -radius * 0.055, y: -radius * 0.33))
      arrow.addLine(to: CGPoint(x: -radius * 0.055, y: radius * 0.13))
      arrow.addLine(to: CGPoint(x: radius * 0.055, y: radius * 0.13))
      arrow.addLine(to: CGPoint(x: radius * 0.055, y: -radius * 0.33))
      arrow.addLine(to: CGPoint(x: radius * 0.15, y: -radius * 0.33))
      arrow.close()
      MikshatStyle.gold.setFill()
      arrow.fill()
    }
    context.restoreGState()
  }
}

final class MikshatCompassViewController: UIViewController, MWMLocationObserver {
  private let target: CLLocationCoordinate2D?
  private let destinationName: String
  private let dial = MikshatCompassDial()
  private let status = MikshatStyle.label(size: 17, color: .white)
  private let speedValue = MikshatStyle.label("—", size: 30, color: MikshatStyle.cyan)
  private let distanceValue = MikshatStyle.label("—", size: 30, color: MikshatStyle.cyan)
  private let durationValue = MikshatStyle.label(L("mikshat_waiting"), size: 22, color: MikshatStyle.cyan)
  private let arrivalValue = MikshatStyle.label("—", size: 25, color: MikshatStyle.cyan)
  private var timer: Timer?
  private var estimate = MikshatTravelEstimate()

  init(target: CLLocationCoordinate2D?, name: String) {
    self.target = target
    destinationName = name
    super.init(nibName: nil, bundle: nil)
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    let qibla = target == nil
    view.backgroundColor = qibla ? UIColor(red: 0.02, green: 0.16, blue: 0.13, alpha: 1) : MikshatStyle.night
    if !qibla {
      let background = UIImageView(image: UIImage(named: "MikshatCompassBackdrop"))
      background.contentMode = .scaleAspectFill
      background.alpha = 0.28
      background.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(background)
      NSLayoutConstraint.activate([background.leadingAnchor.constraint(equalTo: view.leadingAnchor), background.trailingAnchor.constraint(equalTo: view.trailingAnchor), background.topAnchor.constraint(equalTo: view.topAnchor), background.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    }
    let close = MikshatStyle.button("", symbol: "xmark") { [weak self] in self?.dismiss(animated: true) }
    close.configuration?.baseForegroundColor = MikshatStyle.gold
    close.accessibilityLabel = L("close")
    close.heightAnchor.constraint(equalToConstant: 44).isActive = true
    close.widthAnchor.constraint(equalToConstant: 44).isActive = true
    let title = MikshatStyle.label(qibla ? L("mikshat_qibla_title") : destinationName, size: 25, color: qibla ? MikshatStyle.gold : .white)
    let header = UIStackView(arrangedSubviews: qibla ? [UIView(), close] : [close, title])
    header.spacing = 10
    header.semanticContentAttribute = .forceLeftToRight
    if !qibla {
      header.backgroundColor = UIColor.white.withAlphaComponent(0.03)
      header.layer.cornerRadius = 18
      header.layer.borderWidth = 1
      header.layer.borderColor = MikshatStyle.gold.withAlphaComponent(0.5).cgColor
      header.isLayoutMarginsRelativeArrangement = true
      header.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }
    let scroll = UIScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)
    let stack = UIStackView(arrangedSubviews: [header])
    stack.axis = .vertical
    stack.spacing = 20
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(stack)
    dial.backgroundColor = .clear
    dial.qibla = qibla
    if qibla {
      stack.addArrangedSubview(title)
      stack.addArrangedSubview(status)
      let container = UIView()
      dial.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(dial)
      NSLayoutConstraint.activate([
        dial.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.94),
        dial.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        dial.topAnchor.constraint(equalTo: container.topAnchor),
        dial.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])
      stack.addArrangedSubview(container)
    } else { stack.addArrangedSubview(dial) }
    dial.heightAnchor.constraint(equalTo: dial.widthAnchor).isActive = true
    dial.isAccessibilityElement = true
    dial.accessibilityLabel = L(qibla ? "mikshat_qibla" : "mikshat_heading")
    if qibla {
      let kaaba = MikshatKaabaView()
      kaaba.backgroundColor = .clear
      kaaba.translatesAutoresizingMaskIntoConstraints = false
      dial.addSubview(kaaba)
      NSLayoutConstraint.activate([kaaba.centerXAnchor.constraint(equalTo: dial.centerXAnchor), kaaba.centerYAnchor.constraint(equalTo: dial.centerYAnchor), kaaba.widthAnchor.constraint(equalToConstant: 40), kaaba.heightAnchor.constraint(equalToConstant: 44)])
      stack.addArrangedSubview(MikshatStyle.label(L("mikshat_qibla_hint"), size: 18, color: .white))
      let settings = MikshatStyle.button(L("mikshat_location_settings"), symbol: "location") {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
      }
      settings.configuration?.baseForegroundColor = MikshatStyle.gold
      stack.addArrangedSubview(settings)
    } else {
      func card(_ key: String, _ value: UILabel) -> UIView {
        let box = UIStackView(arrangedSubviews: [MikshatStyle.label(L(key), size: 16, color: .white), value])
        box.axis = .vertical
        box.spacing = 8
        box.backgroundColor = UIColor.white.withAlphaComponent(0.03)
        box.layer.cornerRadius = 18
        box.layer.borderWidth = 1
        box.layer.borderColor = MikshatStyle.gold.withAlphaComponent(0.5).cgColor
        box.isLayoutMarginsRelativeArrangement = true
        box.layoutMargins = UIEdgeInsets(top: 14, left: 8, bottom: 14, right: 8)
        return box
      }
      for pair in [[card("mikshat_speed", speedValue), card("mikshat_remaining_distance", distanceValue)],
                   [card("mikshat_remaining_time", durationValue), card("mikshat_arrival", arrivalValue)]] {
        let row = UIStackView(arrangedSubviews: pair)
        row.spacing = 10
        row.distribution = .fillEqually
        stack.addArrangedSubview(row)
      }
      stack.addArrangedSubview(status)
    }
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
      stack.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -28),
    ])
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    LocationManager.add(observer: self)
    LocationManager.start()
    MapsAppDelegate.theApp().disableStandby()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    refresh()
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    timer?.invalidate()
    LocationManager.remove(observer: self)
    MapsAppDelegate.theApp().enableStandby()
  }
  func onLocationUpdate(_ location: CLLocation) { refresh() }
  func onHeadingUpdate(_ heading: CLHeading) { refresh() }
  private func refresh() {
    guard isViewLoaded else { return }
    guard let fix = LocationManager.lastLocation(), fix.horizontalAccuracy >= 0, abs(fix.timestamp.timeIntervalSinceNow) < 15 else {
      dial.bearing = nil
      speedValue.text = "—"; durationValue.text = L("mikshat_waiting"); arrivalValue.text = "—"
      status.text = L("mikshat_location_unavailable")
      return
    }
    let destination = target ?? CLLocationCoordinate2D(latitude: 21.422487, longitude: 39.826206)
    let bearing = MikshatNavigationMath.bearing(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, targetLatitude: destination.latitude, targetLongitude: destination.longitude)
    let heading = LocationManager.lastHeading()
    let mode = target == nil ? 0 : UserDefaults.standard.integer(forKey: "mikshat_heading_mode")
    let gps = MikshatNavigationMath.usesGPS(mode: mode, speed: fix.speed)
    let sensorValid = heading.map { $0.trueHeading >= 0 && $0.headingAccuracy >= 0 && $0.headingAccuracy <= 45 && abs($0.timestamp.timeIntervalSinceNow) < 15 } ?? false
    let gpsValid = fix.course >= 0 && fix.speed >= 0.5 && (fix.courseAccuracy < 0 || fix.courseAccuracy <= 45)
    let valid = gps ? gpsValid : sensorValid
    dial.heading = gps ? max(0, fix.course) : max(0, heading?.trueHeading ?? 0)
    dial.bearing = valid ? bearing : nil
    dial.accessibilityValue = valid ? String(format: "%.0f°", bearing) : L("mikshat_heading_unavailable")
    if target == nil {
      status.text = String(format: L("mikshat_qibla_bearing"), bearing) + (valid ? "" : "\n" + L("mikshat_heading_unavailable"))
    } else {
      let distance = fix.distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
      distanceValue.text = DistanceFormatter.distanceString(fromMeters: distance)
      speedValue.text = fix.speed >= 0 ? "\(Int((fix.speed * 3.6).rounded()))\n\(L("mikshat_kmh"))" : "—"
      let seconds = estimate.update(distance: distance, speed: fix.speed, timestamp: fix.timestamp.timeIntervalSince1970, now: Date().timeIntervalSince1970)
      if let seconds {
        durationValue.text = DurationFormatter.routingDurationString(from: seconds)
        let formatter = DateFormatter(); formatter.timeStyle = .short
        arrivalValue.text = formatter.string(from: Date().addingTimeInterval(seconds))
      } else { durationValue.text = L("mikshat_waiting"); arrivalValue.text = "—" }
      status.text = valid ? L(gps ? "mikshat_heading_gps" : "mikshat_heading_sensor") + " • " + L("mikshat_arrow_to_point") : L("mikshat_heading_unavailable")
    }
  }
}

@objc(MikshatSymbols)
final class MikshatSymbols: NSObject {
  @objc(imageNamed:)
  static func image(named name: String) -> UIImage? {
    let supported = ["gearshape", "mappin.circle", "magnifyingglass", "record.circle", "bookmark", "safari", "arrow.up"]
    guard supported.contains(name) else { return UIImage(systemName: name) }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 42, height: 42))
    return renderer.image { context in
      context.cgContext.translateBy(x: 21, y: 21)
      UIColor.black.setStroke(); UIColor.black.setFill()
      func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, fill: Bool = false) {
        let path = UIBezierPath(ovalIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        path.lineWidth = 2.3
        fill ? path.fill() : path.stroke()
      }
      let path = UIBezierPath()
      path.lineWidth = 2.3
      path.lineCapStyle = .round
      path.lineJoinStyle = .round
      switch name {
      case "gearshape":
        circle(0, 0, 9); circle(0, 0, 3.5)
        for index in 0..<8 {
          let angle = CGFloat(index) * .pi / 4
          path.move(to: CGPoint(x: cos(angle) * 10, y: sin(angle) * 10))
          path.addLine(to: CGPoint(x: cos(angle) * 14, y: sin(angle) * 14))
        }
        path.stroke()
      case "mappin.circle":
        path.move(to: CGPoint(x: 0, y: 14))
        path.addCurve(to: CGPoint(x: 0, y: -17), controlPoint1: CGPoint(x: -19, y: -3), controlPoint2: CGPoint(x: -9, y: -17))
        path.addCurve(to: CGPoint(x: 0, y: 14), controlPoint1: CGPoint(x: 9, y: -17), controlPoint2: CGPoint(x: 19, y: -3))
        path.stroke(); circle(0, -5, 4)
      case "magnifyingglass":
        circle(-3, -3, 10)
        path.move(to: CGPoint(x: 4, y: 4)); path.addLine(to: CGPoint(x: 13, y: 13)); path.stroke()
      case "record.circle":
        circle(0, 0, 13); circle(0, 0, 8, fill: true)
      case "bookmark":
        path.move(to: CGPoint(x: -9, y: -13)); path.addLine(to: CGPoint(x: 9, y: -13))
        path.addLine(to: CGPoint(x: 9, y: 13)); path.addLine(to: CGPoint(x: 0, y: 6))
        path.addLine(to: CGPoint(x: -9, y: 13)); path.close(); path.stroke()
      case "safari":
        circle(0, 0, 14)
        path.move(to: CGPoint(x: -8, y: 8)); path.addLine(to: CGPoint(x: -3, y: -3))
        path.addLine(to: CGPoint(x: 8, y: -8)); path.addLine(to: CGPoint(x: 3, y: 3)); path.close(); path.fill()
      default:
        path.move(to: CGPoint(x: 0, y: -16)); path.addLine(to: CGPoint(x: 12, y: -3))
        path.addLine(to: CGPoint(x: 5, y: -3)); path.addLine(to: CGPoint(x: 5, y: 16))
        path.addLine(to: CGPoint(x: -5, y: 16)); path.addLine(to: CGPoint(x: -5, y: -3))
        path.addLine(to: CGPoint(x: -12, y: -3)); path.close(); path.fill()
      }
    }.withRenderingMode(.alwaysTemplate)
  }
}
