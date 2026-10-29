import UIKit
import CoreLocation

final class MikshatToolsViewController: UIViewController, MWMLocationObserver {
  private let initialTab: Int
  private let tabs = UISegmentedControl(items: [L("mikshat_coordinates"), L("mikshat_qibla"), L("mikshat_heading")])
  private let content = UIStackView()
  private let statusLabel = UILabel()
  private let arrow = UIImageView(image: UIImage(systemName: "location.north.fill"))
  private let latitudeDegrees = UITextField()
  private let latitudeMinutes = UITextField()
  private let longitudeDegrees = UITextField()
  private let longitudeMinutes = UITextField()
  private let latitudeDirection = UISegmentedControl(items: ["N", "S"])
  private let longitudeDirection = UISegmentedControl(items: ["E", "W"])
  private var refreshTimer: Timer?

  init(tab: Int = 0) {
    initialTab = tab
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = L("mikshat_tools")
    view.backgroundColor = .systemGroupedBackground
    view.tintColor = UIColor(red: 22.0 / 255, green: 78.0 / 255, blue: 63.0 / 255, alpha: 1)
    navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    let scrollView = UIScrollView()
    scrollView.keyboardDismissMode = .interactive
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)
    let stack = UIStackView(arrangedSubviews: [tabs, content])
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(stack)
    content.axis = .vertical
    content.spacing = 16
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
      stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
    ])
    tabs.selectedSegmentIndex = initialTab
    tabs.addTarget(self, action: #selector(changeTab), for: .valueChanged)
    for (field, placeholder, label) in [
      (latitudeDegrees, "24", "mikshat_lat_degrees"),
      (latitudeMinutes, "42.810", "mikshat_lat_minutes"),
      (longitudeDegrees, "046", "mikshat_lon_degrees"),
      (longitudeMinutes, "40.518", "mikshat_lon_minutes"),
    ] {
      field.placeholder = placeholder
      field.accessibilityLabel = L(label)
      field.borderStyle = .roundedRect
      field.keyboardType = .decimalPad
      field.font = .preferredFont(forTextStyle: .title3)
      field.adjustsFontForContentSizeCategory = true
      field.textAlignment = .left
      field.semanticContentAttribute = .forceLeftToRight
      field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }
    for field in [latitudeMinutes, longitudeMinutes] {
      field.addTarget(self, action: #selector(formatMinutes(_:)), for: .editingChanged)
    }
    arrow.heightAnchor.constraint(equalToConstant: 160).isActive = true
    latitudeDirection.selectedSegmentIndex = 0
    longitudeDirection.selectedSegmentIndex = 0
    changeTab()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    LocationManager.add(observer: self)
    LocationManager.start()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshQibla() }
    refreshQibla()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    refreshTimer?.invalidate()
    refreshTimer = nil
    LocationManager.remove(observer: self)
  }

  private func label(_ key: String) -> UILabel {
    let result = UILabel()
    result.text = L(key)
    result.numberOfLines = 0
    result.font = .preferredFont(forTextStyle: .body)
    result.adjustsFontForContentSizeCategory = true
    return result
  }

  private func row(_ fields: [UIView]) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: fields)
    stack.axis = .horizontal
    stack.spacing = 8
    stack.distribution = .fillEqually
    stack.semanticContentAttribute = .forceLeftToRight
    return stack
  }

  @objc private func changeTab() {
    view.endEditing(true)
    content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
    switch tabs.selectedSegmentIndex {
    case 0:
      content.addArrangedSubview(label("mikshat_coordinate_hint"))
      content.addArrangedSubview(label("mikshat_latitude"))
      content.addArrangedSubview(row([latitudeDegrees, latitudeMinutes, latitudeDirection]))
      content.addArrangedSubview(label("mikshat_longitude"))
      content.addArrangedSubview(row([longitudeDegrees, longitudeMinutes, longitudeDirection]))
      let button = UIButton(type: .system)
      button.setTitle(L("mikshat_show_map"), for: .normal)
      button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
      button.addTarget(self, action: #selector(showCoordinates), for: .touchUpInside)
      content.addArrangedSubview(button)
    case 1:
      content.addArrangedSubview(label("mikshat_qibla_hint"))
      arrow.contentMode = .scaleAspectFit
      arrow.tintColor = UIColor(red: 235.0 / 255, green: 164.0 / 255, blue: 38.0 / 255, alpha: 1)
      arrow.isAccessibilityElement = true
      arrow.accessibilityLabel = L("mikshat_qibla")
      content.addArrangedSubview(arrow)
      statusLabel.numberOfLines = 0
      statusLabel.font = .preferredFont(forTextStyle: .title3)
      statusLabel.adjustsFontForContentSizeCategory = true
      statusLabel.textAlignment = .center
      content.addArrangedSubview(statusLabel)
      refreshQibla()
    default:
      content.addArrangedSubview(label("mikshat_heading_hint"))
      let modes = ["mikshat_heading_sensor", "mikshat_heading_gps", "mikshat_heading_auto"]
      let selected = UserDefaults.standard.integer(forKey: "mikshat_heading_mode")
      for (index, key) in modes.enumerated() {
        let button = UIButton(type: .system)
        button.setTitle(L(key), for: .normal)
        button.setImage(UIImage(systemName: index == selected ? "checkmark.circle.fill" : "circle"), for: .normal)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.tag = index
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        button.addTarget(self, action: #selector(selectHeading(_:)), for: .touchUpInside)
        content.addArrangedSubview(button)
      }
    }
  }

  @objc private func formatMinutes(_ field: UITextField) {
    field.text = MikshatNavigationMath.minuteInput(field.text ?? "")
  }

  @objc private func selectHeading(_ sender: UIButton) {
    UserDefaults.standard.set(sender.tag, forKey: "mikshat_heading_mode")
    changeTab()
  }

  @objc private func showCoordinates() {
    do {
      let lat = try MikshatNavigationMath.coordinate(degrees: latitudeDegrees.text ?? "", minutes: latitudeMinutes.text ?? "",
                                                   latitude: true, negative: latitudeDirection.selectedSegmentIndex == 1)
      let lon = try MikshatNavigationMath.coordinate(degrees: longitudeDegrees.text ?? "", minutes: longitudeMinutes.text ?? "",
                                                   latitude: false, negative: longitudeDirection.selectedSegmentIndex == 1)
      let coordinates = String(format: "%.8f,%.8f", locale: Locale(identifier: "en_US_POSIX"), lat, lon)
      guard let url = URL(string: "om://map?ll=\(coordinates)") else { return }
      if presentingViewController != nil || navigationController?.presentingViewController != nil {
        dismiss(animated: true) { _ = DeepLinkHandler.shared.applicationDidOpenUrl(url) }
      } else {
        _ = DeepLinkHandler.shared.applicationDidOpenUrl(url)
      }
    } catch {
      let alert = UIAlertController(title: L("mikshat_coordinates"), message: L("mikshat_coordinate_error"), preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: L("ok"), style: .default))
      present(alert, animated: true)
    }
  }

  @objc private func close() {
    if navigationController?.presentingViewController != nil { dismiss(animated: true) }
    else { navigationController?.popViewController(animated: true) }
  }

  func onLocationUpdate(_ location: CLLocation) { refreshQibla() }
  func onHeadingUpdate(_ heading: CLHeading) { refreshQibla() }
  func onLocationError(_ error: MWMLocationStatus) { refreshQibla() }

  private func refreshQibla() {
    guard isViewLoaded, tabs.selectedSegmentIndex == 1 else { return }
    guard let location = LocationManager.lastLocation(), location.horizontalAccuracy >= 0,
          abs(location.timestamp.timeIntervalSinceNow) <= 30 else {
      arrow.isHidden = true
      statusLabel.text = L("mikshat_location_unavailable")
      return
    }
    let bearing = MikshatNavigationMath.bearing(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    let direction = String(format: L("mikshat_qibla_bearing"), bearing)
    guard let heading = LocationManager.lastHeading(), heading.trueHeading >= 0,
          heading.headingAccuracy >= 0, heading.headingAccuracy <= 45,
          abs(heading.timestamp.timeIntervalSinceNow) <= 30 else {
      arrow.isHidden = true
      statusLabel.text = direction + "\n" + L("mikshat_heading_unavailable")
      return
    }
    arrow.isHidden = false
    arrow.transform = CGAffineTransform(rotationAngle: CGFloat((bearing - heading.trueHeading) * .pi / 180))
    statusLabel.text = direction
    arrow.accessibilityValue = direction
  }
}
