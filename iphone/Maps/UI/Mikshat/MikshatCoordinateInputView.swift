import UIKit
import CoreLocation

final class MikshatCoordinateInputView: UIStackView {
  var onSubmit: ((CLLocationCoordinate2D) -> Void)?
  private let latDegrees = UITextField()
  private let latMinutes = UITextField()
  private let lonDegrees = UITextField()
  private let lonMinutes = UITextField()
  private let latitudeDirection = UISegmentedControl(items: ["N", "S"])
  private let longitudeDirection = UISegmentedControl(items: ["E", "W"])
  private let errorLabel = MikshatStyle.label(size: 13, color: .systemRed)

  init() {
    super.init(frame: .zero)
    axis = .vertical
    spacing = 7
    addArrangedSubview(MikshatStyle.label(L("mikshat_enter_coordinates"), size: 17, color: MikshatStyle.green))
    for (degrees, minutes, direction, placeholders, keys) in [
      (latDegrees, latMinutes, latitudeDirection, ["00", "00.000"], ["mikshat_lat_degrees", "mikshat_lat_minutes"]),
      (lonDegrees, lonMinutes, longitudeDirection, ["000", "00.000"], ["mikshat_lon_degrees", "mikshat_lon_minutes"]),
    ] {
      for (index, field) in [degrees, minutes].enumerated() {
        field.placeholder = placeholders[index]
        field.keyboardType = .decimalPad
        field.font = .preferredFont(forTextStyle: .title3)
        field.adjustsFontForContentSizeCategory = true
        field.textAlignment = .center
        field.accessibilityLabel = L(keys[index])
        field.semanticContentAttribute = .forceLeftToRight
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
      }
      degrees.widthAnchor.constraint(equalTo: minutes.widthAnchor, multiplier: 0.65).isActive = true
      minutes.addTarget(self, action: #selector(formatMinutes(_:)), for: .editingChanged)
      direction.selectedSegmentIndex = 0
      direction.widthAnchor.constraint(equalToConstant: 78).isActive = true
      let row = UIStackView(arrangedSubviews: [direction, degrees, MikshatStyle.label("°", color: MikshatStyle.green), minutes, MikshatStyle.label("′", color: MikshatStyle.green)])
      row.axis = .horizontal
      row.spacing = 5
      row.semanticContentAttribute = .forceLeftToRight
      row.backgroundColor = MikshatStyle.green.withAlphaComponent(0.05)
      row.layer.cornerRadius = 10
      row.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
      addArrangedSubview(row)
    }
    let show = UIButton(type: .system)
    var config = UIButton.Configuration.filled()
    config.title = L("mikshat_show_map")
    config.baseBackgroundColor = MikshatStyle.green
    config.baseForegroundColor = .white
    config.cornerStyle = .medium
    show.configuration = config
    show.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    show.addTarget(self, action: #selector(submit), for: .touchUpInside)
    addArrangedSubview(show)
    errorLabel.isHidden = true
    addArrangedSubview(errorLabel)
  }
  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc private func formatMinutes(_ field: UITextField) {
    field.text = MikshatNavigationMath.minuteInput(field.text ?? "")
  }
  @objc private func submit() {
    do {
      let latitude = try MikshatNavigationMath.coordinate(degrees: latDegrees.text ?? "", minutes: latMinutes.text ?? "", latitude: true, negative: latitudeDirection.selectedSegmentIndex == 1)
      let longitude = try MikshatNavigationMath.coordinate(degrees: lonDegrees.text ?? "", minutes: lonMinutes.text ?? "", latitude: false, negative: longitudeDirection.selectedSegmentIndex == 1)
      errorLabel.isHidden = true
      endEditing(true)
      onSubmit?(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    } catch {
      errorLabel.text = L("mikshat_coordinate_error")
      errorLabel.isHidden = false
      UIAccessibility.post(notification: .announcement, argument: errorLabel.text)
    }
  }
}
