final class PlacePageDirectionView: UIView {
  @IBOutlet var imageView: UIImageView!
  @IBOutlet var label: UILabel!
  override func layoutSubviews() {
    super.layoutSubviews()
    let font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 18.2))
    if label.font.pointSize != font.pointSize { label.font = font }
  }
  override func awakeFromNib() {
    super.awakeFromNib()
    label.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 18.2))
    label.adjustsFontForContentSizeCategory = true
    for constraint in imageView.constraints where constraint.firstAttribute == .width || constraint.firstAttribute == .height {
      if constraint.secondItem == nil { constraint.constant *= 1.3 }
    }
  }
}

/// All formats belong to the selected map point, independently of GPS updates or format preferences.
final class PlacePageCoordinatesView: UIStackView {
  private let toggleButton = UIButton(type: .system)
  private let additionalRows: [UIView]
  private let didChangeExpanded: () -> Void
  private(set) var isExpanded = false

  init(coordinate: CLLocationCoordinate2D,
       copy: @escaping (String) -> Void,
       didChangeExpanded: @escaping () -> Void) {
    let formats = MikshatNavigationMath.coordinatePairs(latitude: coordinate.latitude, longitude: coordinate.longitude)
    additionalRows = [("DD", formats[0]), ("DMS", formats[2])].map { format, text in
      PlacePageCoordinateFormatRow(text: text, format: format, copy: { copy(text) })
    }
    self.didChangeExpanded = didChangeExpanded
    super.init(frame: .zero)
    axis = .vertical
    alignment = .fill
    spacing = 0
    accessibilityIdentifier = "placePage.coordinates"

    var configuration = UIButton.Configuration.filled()
    configuration.image = UIImage(systemName: "line.3.horizontal")
    configuration.baseBackgroundColor = MikshatStyle.green
    configuration.baseForegroundColor = .white
    configuration.cornerStyle = .medium
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 21)
    toggleButton.configuration = configuration
    toggleButton.accessibilityIdentifier = "placePage.coordinates.toggle"
    toggleButton.accessibilityLabel = L("mikshat_coordinate_formats")
    toggleButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
    toggleButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    toggleButton.addAction(UIAction { [weak self] _ in self?.toggleExpanded() }, for: .touchUpInside)

    addArrangedSubview(PlacePageCoordinateFormatRow(text: formats[1],
                                                   format: "DDM",
                                                   accessory: toggleButton,
                                                   copy: { copy(formats[1]) }))
    updateExpandedAccessibility()
  }

  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func toggleExpanded() {
    isExpanded.toggle()
    for row in additionalRows {
      if isExpanded {
        addArrangedSubview(row)
      } else {
        removeArrangedSubview(row)
        row.removeFromSuperview()
      }
    }
    updateExpandedAccessibility()
    invalidateIntrinsicContentSize()
    didChangeExpanded()
    UIAccessibility.post(notification: .layoutChanged, argument: toggleButton)
  }

  private func updateExpandedAccessibility() {
    toggleButton.accessibilityValue = L(isExpanded ? "mikshat_expanded" : "mikshat_collapsed")
    toggleButton.isSelected = isExpanded
  }
}

private final class PlacePageCoordinateFormatRow: UIStackView {
  init(text: String, format: String, accessory: UIView? = nil, copy: @escaping () -> Void) {
    super.init(frame: .zero)
    axis = .horizontal
    alignment = .center
    spacing = 8
    semanticContentAttribute = .forceLeftToRight
    isLayoutMarginsRelativeArrangement = true
    layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    let identifier = "placePage.coordinates.\(format.lowercased())"
    accessibilityIdentifier = identifier

    let copyButton = UIButton(type: .system)
    var configuration = UIButton.Configuration.filled()
    configuration.title = L("mikshat_copy")
    configuration.baseBackgroundColor = MikshatStyle.green
    configuration.baseForegroundColor = .white
    configuration.cornerStyle = .medium
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var attributes = incoming
      attributes.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 17), maximumPointSize: 20)
      return attributes
    }
    copyButton.configuration = configuration
    copyButton.accessibilityIdentifier = identifier + ".copy"
    copyButton.accessibilityLabel = String(format: L("mikshat_copy_coordinates_format"), format)
    copyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    copyButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    copyButton.setContentHuggingPriority(.required, for: .horizontal)
    copyButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    copyButton.addAction(UIAction { _ in copy() }, for: .touchUpInside)
    addArrangedSubview(copyButton)

    let values = UIStackView()
    values.axis = .vertical
    values.alignment = .fill
    values.spacing = 3
    let formatLabel = MikshatStyle.label(format, size: 12, color: MikshatStyle.green)
    formatLabel.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 12), maximumPointSize: 16)
    formatLabel.textAlignment = .left
    values.addArrangedSubview(formatLabel)
    for (index, line) in text.components(separatedBy: "\n").enumerated() {
      let label = MikshatStyle.label(line, size: 18, color: MikshatStyle.green)
      label.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 18), maximumPointSize: 24)
      label.numberOfLines = 1
      label.textAlignment = .left
      label.semanticContentAttribute = .forceLeftToRight
      label.adjustsFontSizeToFitWidth = true
      label.minimumScaleFactor = 0.5
      label.accessibilityIdentifier = identifier + (index == 0 ? ".latitude" : ".longitude")
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      values.addArrangedSubview(label)
    }
    values.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    addArrangedSubview(values)
    if let accessory { addArrangedSubview(accessory) }
    setContentHuggingPriority(.required, for: .vertical)
    setContentCompressionResistancePriority(.required, for: .vertical)
  }

  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class PlacePagePreviewViewController: UIViewController {
  @IBOutlet var stackView: UIStackView!
  @IBOutlet var popularView: UIView!
  @IBOutlet var subtitleLabel: UILabel!
  @IBOutlet var subtitleContainerView: UIStackView!
  @IBOutlet var scheduleLabel: UILabel!
  @IBOutlet var reviewsLabel: UILabel!
  @IBOutlet var addReviewButton: UIButton! {
    didSet {
      addReviewButton.setTitle("+ \(L("leave_a_review"))", for: .normal)
    }
  }

  @IBOutlet var addressLabel: UILabel!
  @IBOutlet var addressContainerView: UIStackView!
  @IBOutlet var scheduleContainerView: UIStackView!

  @IBOutlet var subtitleDirectionView: PlacePageDirectionView!
  @IBOutlet var addressDirectionView: PlacePageDirectionView!

  var placePageDirectionView: PlacePageDirectionView?
  private var loadedDirectionView: DirectionView?
  var fullScreenDirectionView: DirectionView {
    if let loadedDirectionView { return loadedDirectionView }
    let view: DirectionView = Bundle.main.load(viewClass: DirectionView.self)!
    loadedDirectionView = view
    return view
  }

  var placePagePreviewData: PlacePagePreviewData! {
    didSet {
      if isViewLoaded {
        updateViews()
      }
    }
  }

  weak var delegate: PlacePageHeaderViewControllerDelegate?

  var mikshatCoordinate: CLLocationCoordinate2D?
  private var distance: String?
  private var speedAndAltitude: String?
  private var heading: CGFloat?

  override func viewDidLoad() {
    super.viewDidLoad()

    updateViews()
    if let coordinate = mikshatCoordinate {
      stackView.addArrangedSubview(PlacePageCoordinatesView(coordinate: coordinate,
                                                           copy: { [weak self] text in self?.delegate?.previewDidCopy(text) },
                                                           didChangeExpanded: { [weak self] in self?.delegate?.previewDidChangeContentSize() }))
    }

    subtitleLabel.adjustsFontForContentSizeCategory = true
    scheduleLabel.adjustsFontForContentSizeCategory = true

    if let distance = distance {
      placePageDirectionView?.isHidden = false
      placePageDirectionView?.label.text = distance
    }

    if let heading = heading {
      updateHeading(heading)
    } else {
      placePageDirectionView?.imageView.isHidden = true
    }
  }

  func updateViews() {
    if placePagePreviewData.isMyPosition {
      if let speedAndAltitude = speedAndAltitude {
        subtitleLabel.text = speedAndAltitude
      }
    } else {
      let subtitleString = NSMutableAttributedString()
//      if placePagePreviewData.isPopular {
//        subtitleString.append(NSAttributedString(string: L("popular_place"),
//                                                 attributes: [.foregroundColor : UIColor.linkBlue,
//                                                              .font : UIFont.regular14]))
//      }

      let subtitle = placePagePreviewData.subtitle ?? (mikshatCoordinate == nil ? placePagePreviewData.coordinates : nil)
      if let subtitle {
        subtitleString.append(NSAttributedString(string: !subtitleString.string.isEmpty ? " • " + subtitle : subtitle,
                                                 attributes: [.foregroundColor: UIColor.blackSecondaryText,
                                                              .font: UIFont.emojiRegular14.dynamic]))

        subtitleLabel.attributedText = subtitleString
        subtitleLabel.isHidden = false
        subtitleContainerView.isHidden = false
      } else {
        subtitleLabel.text = nil
        subtitleLabel.isHidden = true
        subtitleContainerView.isHidden = true
      }
    }

    placePageDirectionView = subtitleDirectionView

    if let address = placePagePreviewData.secondarySubtitle {
      addressLabel.text = address
      placePageDirectionView = addressDirectionView
    } else {
      addressContainerView.isHidden = true
    }
    if placePageDirectionView === subtitleDirectionView, distance != nil {
      subtitleContainerView.isHidden = false
    }
    placePageDirectionView?.imageView.changeColoringToOpposite()
    configSchedule()
  }

  func updateDistance(_ distance: String) {
    self.distance = distance
    placePageDirectionView?.isHidden = false
    placePageDirectionView?.label.text = distance
    if placePageDirectionView === subtitleDirectionView {
      subtitleContainerView?.isHidden = false
    }
    loadedDirectionView?.updateDistance(distance)
  }

  func clearHeading() {
    heading = nil
    placePageDirectionView?.imageView.isHidden = true
    loadedDirectionView?.setHeadingAvailable(false)
  }

  func updateHeading(_ angle: CGFloat) {
    loadedDirectionView?.setHeadingAvailable(true)
    placePageDirectionView?.imageView.isHidden = false
    let duration = heading == nil ? .zero : AppConstants.defaultAnimationDuration // skip the initial setup animation
    UIView.animate(withDuration: duration,
                   delay: 0,
                   options: [.beginFromCurrentState, .curveEaseInOut],
                   animations: { [unowned self] in
                     placePageDirectionView?.imageView.transform = CGAffineTransform(rotationAngle: CGFloat.pi / 2 - angle)
                   })
    loadedDirectionView?.updateHeading(angle)
    heading = angle
  }

  func updateSpeedAndAltitude(_ speedAndAltitude: String) {
    self.speedAndAltitude = speedAndAltitude
    subtitleLabel?.text = speedAndAltitude
  }

  @IBAction func onLongPressAdress(_ sender: UILongPressGestureRecognizer) {
    guard let address = addressLabel.text, sender.state == .began else { return }
    delegate?.previewDidCopy(address)
  }

  @IBAction func onDirectionPressed(_: Any) {
    guard let heading = heading else {
      return
    }

    fullScreenDirectionView.updateTitle(placePagePreviewData.title,
                                        subtitle: placePagePreviewData.subtitle ?? placePagePreviewData.coordinates)
    fullScreenDirectionView.setHeadingAvailable(true)
    fullScreenDirectionView.updateHeading(heading)
    fullScreenDirectionView.updateDistance(distance)
    fullScreenDirectionView.show()
  }

  // MARK: private

  private func configSchedule() {
    let now = time_t(Date().timeIntervalSince1970)

    func stringFromTime(_ time: Int) -> String {
      DateTimeFormatter.dateString(from: Date(timeIntervalSince1970: TimeInterval(time)),
                                   dateStyle: .none,
                                   timeStyle: .short)
    }

    switch placePagePreviewData.schedule.state {
    case .unknown:
      scheduleContainerView.isHidden = true

    case .allDay:
      setScheduleLabel(state: L("twentyfour_seven"),
                       stateColor: UIColor.systemGreen,
                       details: nil)

    case .open:
      let nextTimeClosed = placePagePreviewData.schedule.nextTimeClosed
      let minutesUntilClosed = (nextTimeClosed - now) / 60
      let stringTimeInterval = getTimeIntervalString(minutes: minutesUntilClosed)
      let stringTime = stringFromTime(nextTimeClosed)

      let details: String?
      if minutesUntilClosed < 3 * 60 // Less than 3 hours
      {
        details = String(format: L("closes_in"), stringTimeInterval) + " • " + stringTime
      } else if minutesUntilClosed < 24 * 60 // Less than 24 hours
      {
        details = String(format: L("closes_at"), stringTime)
      } else {
        details = nil
      }

      setScheduleLabel(state: L("editor_time_open"),
                       stateColor: UIColor.systemGreen,
                       details: details)

    case .closed:
      let nextTimeOpen = placePagePreviewData.schedule.nextTimeOpen
      let nextTimeOpenDate = Date(timeIntervalSince1970: TimeInterval(nextTimeOpen))

      let minutesUntilOpen = (nextTimeOpen - now) / 60
      let stringTimeInterval = getTimeIntervalString(minutes: minutesUntilOpen)
      let stringTime = stringFromTime(nextTimeOpen)

      let details: String?
      if minutesUntilOpen < 3 * 60 // Less than 3 hours
      {
        details = String(format: L("opens_in"), stringTimeInterval) + " • " + stringTime
      } else if Calendar.current.isDateInToday(nextTimeOpenDate) // Today
      {
        details = String(format: L("opens_at"), stringTime)
      } else if minutesUntilOpen < 24 * 60 // Less than 24 hours
      {
        details = String(format: L("opens_tomorrow_at"), stringTime)
      } else if minutesUntilOpen < 7 * 24 * 60 // Less than 1 week
      {
        let dayOfWeek = DateTimeFormatter.dateString(from: nextTimeOpenDate, format: "EEEE")
        details = String(format: L("opens_dayoftheweek_at"), dayOfWeek, stringTime)
      } else {
        details = nil
      }

      setScheduleLabel(state: L("closed_now"),
                       stateColor: UIColor.systemRed,
                       details: details)

    @unknown default:
      fatalError()
    }
  }

  private func getTimeIntervalString(minutes: Int) -> String {
    var str = ""
    if minutes >= 60 {
      str = String(minutes / 60) + " " + L("hour") + " "
    }
    str += String(minutes % 60) + " " + L("minute")
    return str
  }

  private func setScheduleLabel(state: String, stateColor: UIColor, details: String?) {
    let attributedString = NSMutableAttributedString()
    let stateString = NSAttributedString(string: state,
                                         attributes: [NSAttributedString.Key.font: UIFont.regular14.dynamic,
                                                      NSAttributedString.Key.foregroundColor: stateColor])
    attributedString.append(stateString)
    if details != nil {
      let detailsString = NSAttributedString(string: " • " + details!,
                                             attributes: [NSAttributedString.Key.font: UIFont.regular14.dynamic,
                                                          NSAttributedString.Key.foregroundColor: UIColor.blackSecondaryText])
      attributedString.append(detailsString)
    }
    scheduleLabel.attributedText = attributedString
  }
}
