final class SearchHistoryCell: MWMTableViewCell {
  enum Content {
    case query(String)
    case location(MikshatSearchLocation)
    case clear
  }

  private let directionIndicator = MikshatDirectionIndicator()

  private static let placeholderImage = UIImage.filled(with: .clear, size: CGSize(width: 28, height: 28))

  override init(style _: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    setStyle(.defaultTableViewCell)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    directionIndicator.target = nil
    accessoryView = nil
    detailTextLabel?.text = nil
  }

  func configure(for content: Content) {
    directionIndicator.target = nil
    accessoryView = nil
    detailTextLabel?.text = nil
    switch content {
    case .query(let query):
      textLabel?.text = query
      if let coordinate = MikshatSearchLocations.coordinate(for: query) {
        directionIndicator.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        directionIndicator.target = coordinate
        accessoryView = directionIndicator
      } else {
        detailTextLabel?.text = L("mikshat_history_resolve_location")
      }
      textLabel?.setFontStyleAndApply(.regular17, color: .blackSecondary)
      imageView?.image = UIImage(resource: .icSearch)
      imageView?.setStyleAndApply(.black)
      isSeparatorHidden = false
    case .location(let location):
      textLabel?.text = location.title
      let pair = String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"),
                         location.latitude, location.longitude)
      detailTextLabel?.text = location.subtitle.isEmpty ? pair : location.subtitle + " · " + pair
      directionIndicator.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
      directionIndicator.target = location.coordinate
      accessoryView = directionIndicator
      textLabel?.setFontStyleAndApply(.regular17, color: .blackSecondary)
      imageView?.image = UIImage(systemName: "mappin")
      imageView?.setStyleAndApply(.black)
      isSeparatorHidden = false
    case .clear:
      textLabel?.text = L("clear_search")
      textLabel?.setFontStyleAndApply(.regular14, color: .linkBlue)
      imageView?.image = Self.placeholderImage
      isSeparatorHidden = true
    }
    detailTextLabel?.setFontStyleAndApply(.regular12, color: .blackSecondary)
    detailTextLabel?.numberOfLines = 2
  }
}
