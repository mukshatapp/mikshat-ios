import UIKit
import CoreLocation

final class MikshatCoordinateInputView: UIStackView, UITextFieldDelegate {
  var onSubmit: ((CLLocationCoordinate2D) -> Void)?
  private let latDegrees = UITextField()
  private let latMinutes = UITextField()
  private let lonDegrees = UITextField()
  private let lonMinutes = UITextField()
  private let latitudeDirection = UISegmentedControl(items: ["N", "S"])
  private let longitudeDirection = UISegmentedControl(items: ["E", "W"])
  private let errorLabel = MikshatStyle.label(size: 13, color: .systemRed)

  private let show = UIButton(type: .system)
  private var counts: [ObjectIdentifier: Int] = [:]
  private var fields: [UITextField] { [latDegrees, latMinutes, lonDegrees, lonMinutes] }

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
        field.delegate = self
        field.addTarget(self, action: #selector(fieldChanged(_:)), for: .editingChanged)
        field.keyboardType = .decimalPad
        field.font = .preferredFont(forTextStyle: .title3)
        field.adjustsFontForContentSizeCategory = true
        field.textAlignment = .center
        field.accessibilityLabel = L(keys[index])
        field.semanticContentAttribute = .forceLeftToRight
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
      }
      direction.selectedSegmentIndex = 0
      direction.widthAnchor.constraint(equalToConstant: 78).isActive = true
      let row = UIStackView(arrangedSubviews: [direction, degrees, MikshatStyle.label("°", color: MikshatStyle.green), minutes, MikshatStyle.label("′", color: MikshatStyle.green)])
      // Both fields must share an ancestor before activating a constraint between them.
      degrees.widthAnchor.constraint(equalTo: minutes.widthAnchor, multiplier: 0.65).isActive = true
      row.axis = .horizontal
      row.spacing = 5
      row.semanticContentAttribute = .forceLeftToRight
      row.backgroundColor = MikshatStyle.green.withAlphaComponent(0.05)
      row.layer.cornerRadius = 10
      row.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
      addArrangedSubview(row)
    }
    var config = UIButton.Configuration.filled()
    config.title = L("mikshat_show_map")
    config.baseBackgroundColor = MikshatStyle.green
    config.baseForegroundColor = .white
    config.cornerStyle = .medium
    show.configuration = config
    show.isEnabled = false
    latitudeDirection.addTarget(self, action: #selector(validateInput), for: .valueChanged)
    longitudeDirection.addTarget(self, action: #selector(validateInput), for: .valueChanged)
    show.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    show.addTarget(self, action: #selector(submit), for: .touchUpInside)
    addArrangedSubview(show)
    errorLabel.isHidden = true
    addArrangedSubview(errorLabel)
  }
  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private func limit(for field: UITextField) -> Int {
    field === latDegrees ? 2 : (field === lonDegrees ? 3 : 5)
  }

  func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
    let current = field.text ?? ""
    guard let swiftRange = Range(range, in: current) else { return false }
    var changedRange = range
    // Deleting the automatic decimal separator removes the preceding digit as well.
    if string.isEmpty, current[swiftRange] == ".", range.location > 0 {
      changedRange = NSRange(location: range.location - 1, length: range.length + 1)
    }
    let raw = (current as NSString).replacingCharacters(in: changedRange, with: string)
    let normalized = MikshatNavigationMath.ascii(raw)
    guard normalized.allSatisfy({ $0.isNumber || $0 == "." }) else { return false }
    let digits = String(normalized.filter { $0.isNumber }.prefix(limit(for: field)))
    let prefix = (current as NSString).substring(to: changedRange.location) + string
    let digitsBeforeCursor = min(digits.count, MikshatNavigationMath.ascii(prefix).filter { $0.isNumber }.count)
    let minutes = field === latMinutes || field === lonMinutes
    field.text = minutes ? MikshatNavigationMath.minuteInput(digits) : digits
    let offset = digitsBeforeCursor + (minutes && digitsBeforeCursor >= 2 ? 1 : 0)
    if let position = field.position(from: field.beginningOfDocument, offset: offset) {
      field.selectedTextRange = field.textRange(from: position, to: position)
    }
    field.sendActions(for: .editingChanged)
    return false
  }

  @objc private func fieldChanged(_ field: UITextField) {
    let index = fields.firstIndex { $0 === field }!
    let digits = String(MikshatNavigationMath.ascii(field.text ?? "").filter { $0.isNumber }.prefix(limit(for: field)))
    let oldCount = counts[ObjectIdentifier(field)] ?? 0
    counts[ObjectIdentifier(field)] = digits.count
    let formatted = index == 1 || index == 3 ? MikshatNavigationMath.minuteInput(digits) : digits
    if field.text != formatted { field.text = formatted }
    validateInput()
    let cursorAtEnd = field.selectedTextRange.map { field.offset(from: $0.end, to: field.endOfDocument) == 0 } ?? true
    if digits.count == limit(for: field), oldCount < digits.count, cursorAtEnd {
      if index < fields.count - 1 { fields[index + 1].becomeFirstResponder() }
      else {
        field.resignFirstResponder()
        if show.isEnabled { UIAccessibility.post(notification: .layoutChanged, argument: show) }
      }
    }
  }

  private func coordinate() throws -> CLLocationCoordinate2D {
    let latitude = try MikshatNavigationMath.coordinate(degrees: latDegrees.text ?? "", minutes: latMinutes.text ?? "", latitude: true, negative: latitudeDirection.selectedSegmentIndex == 1)
    let longitude = try MikshatNavigationMath.coordinate(degrees: lonDegrees.text ?? "", minutes: lonMinutes.text ?? "", latitude: false, negative: longitudeDirection.selectedSegmentIndex == 1)
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  @objc private func validateInput() {
    let complete = fields.allSatisfy { MikshatNavigationMath.ascii($0.text ?? "").filter { $0.isNumber }.count == limit(for: $0) }
    let valid = (try? coordinate()) != nil
    show.isEnabled = complete && valid
    errorLabel.isHidden = !complete || valid
    errorLabel.text = L("mikshat_coordinate_error")
  }
  @objc private func submit() {
    guard show.isEnabled else { return }
    do {
      let value = try coordinate()
      errorLabel.isHidden = true
      endEditing(true)
      onSubmit?(value)
    } catch {
      errorLabel.text = L("mikshat_coordinate_error")
      errorLabel.isHidden = false
      UIAccessibility.post(notification: .announcement, argument: errorLabel.text)
    }
  }
}
