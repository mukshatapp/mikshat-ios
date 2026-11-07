final class SearchHistoryCell: MWMTableViewCell {
  enum Content {
    case query(String)
    case clear
  }

  private let directionIndicator = MikshatDirectionIndicator()

  private static let placeholderImage = UIImage.filled(with: .clear, size: CGSize(width: 28, height: 28))

  override init(style _: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: .default, reuseIdentifier: reuseIdentifier)
    setStyle(.defaultTableViewCell)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(for content: Content) {
    directionIndicator.target = nil
    accessoryView = nil
    switch content {
    case .query(let query):
      textLabel?.text = query
      if let coordinate = MikshatSearchLocations.coordinate(for: query) {
        directionIndicator.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        directionIndicator.target = coordinate
        accessoryView = directionIndicator
      }
      textLabel?.setFontStyleAndApply(.regular17, color: .blackSecondary)
      imageView?.image = UIImage(resource: .icSearch)
      imageView?.setStyleAndApply(.black)
      isSeparatorHidden = false
    case .clear:
      textLabel?.text = L("clear_search")
      textLabel?.setFontStyleAndApply(.regular14, color: .linkBlue)
      imageView?.image = Self.placeholderImage
      isSeparatorHidden = true
    }
  }
}
