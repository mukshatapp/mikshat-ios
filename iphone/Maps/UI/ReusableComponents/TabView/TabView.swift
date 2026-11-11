private class TabContentFlowLayout: UICollectionViewFlowLayout {
  override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
    let sizeChanged = collectionView.map { $0.bounds.size != newBounds.size } ?? false
    return sizeChanged || super.shouldInvalidateLayout(forBoundsChange: newBounds)
  }

  override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
    let context = super.invalidationContext(forBoundsChange: newBounds)
    if let collectionView, collectionView.bounds.size != newBounds.size,
       let flowContext = context as? UICollectionViewFlowLayoutInvalidationContext {
      flowContext.invalidateFlowLayoutDelegateMetrics = true
      flowContext.invalidateFlowLayoutAttributes = true
    }
    return context
  }
}

private class ContentCell: UICollectionViewCell {
  var view: UIView? {
    didSet {
      if let view = view, view != oldValue {
        oldValue?.removeFromSuperview()
        view.frame = contentView.bounds
        contentView.addSubview(view)
      }
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if let view = view {
      view.frame = contentView.bounds
    }
  }
}

private class HeaderCell: UICollectionViewCell {
  private let label = UILabel()
  private var selectedAttributes: [NSAttributedString.Key: Any] = [:]
  private var deselectedAttributes: [NSAttributedString.Key: Any] = [:]

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(label)
    label.textAlignment = .center
  }

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    contentView.addSubview(label)
    label.textAlignment = .center
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    label.text = nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    label.frame = contentView.bounds
  }

  func configureWith(selectedAttributes: [NSAttributedString.Key: Any],
                     deselectedAttributes: [NSAttributedString.Key: Any],
                     text: String,
                     selectionProgress: CGFloat) {
    self.selectedAttributes = selectedAttributes
    self.deselectedAttributes = deselectedAttributes
    label.text = text.uppercased()
    label.font = deselectedAttributes[.font] as? UIFont
    label.adjustsFontForContentSizeCategory = true
    label.configureSingleLineAutoScaling()
    updateSelectionProgress(selectionProgress)
  }

  func updateSelectionProgress(_ selectionProgress: CGFloat) {
    let selectionProgress = max(0, min(1, selectionProgress))
    let deselectedColor = deselectedAttributes[.foregroundColor] as? UIColor
    let selectedColor = selectedAttributes[.foregroundColor] as? UIColor

    if let deselectedColor, let selectedColor {
      label.textColor = deselectedColor.interpolated(to: selectedColor, progress: selectionProgress)
    } else {
      label.textColor = deselectedColor ?? selectedColor
    }
  }
}

protocol TabViewDataSource: AnyObject {
  func numberOfPages(in tabView: TabView) -> Int
  func tabView(_ tabView: TabView, viewAt index: Int) -> UIView
  func tabView(_ tabView: TabView, titleAt index: Int) -> String?
}

protocol TabViewDelegate: AnyObject {
  func tabView(_ tabView: TabView, didSelectTabAt index: Int)
}

@objcMembers
class TabView: UIView {
  private enum CellId {
    static let content = "contentCell"
    static let header = "headerCell"
  }

  private let tabsLayout = UICollectionViewFlowLayout()
  private let tabsContentLayout: UICollectionViewFlowLayout = TabContentFlowLayout()
  private let tabsCollectionView: UICollectionView
  private let tabsContentCollectionView: UICollectionView
  private let headerView = UIView()
  private let slidingView = UIView()
  private var headerViewHeight: NSLayoutConstraint!
  private var slidingViewLeft: NSLayoutConstraint!
  private var slidingViewWidth: NSLayoutConstraint!
  private var slidingViewHeight: NSLayoutConstraint!
  private var pageCount: Int { max(0, dataSource?.numberOfPages(in: self) ?? 0) }
  private var lastHeaderSize: CGSize = .zero
  private var lastContentSize: CGSize = .zero
  var selectedIndex: Int? {
    didSet {
      updateSelectedHeader()
    }
  }

  var showsTabBar = true {
    didSet {
      updateTabBarVisibility()
    }
  }

  private var lastSelectedIndex: Int?

  weak var dataSource: TabViewDataSource?
  weak var delegate: TabViewDelegate?

  var barTintColor = UIColor.white {
    didSet {
      headerView.backgroundColor = barTintColor
    }
  }

  var selectedHeaderTextAttributes: [NSAttributedString.Key: Any] = [
    .foregroundColor: UIColor.white,
    .font: UIFont.semibold14.dynamic,
  ] {
    didSet {
      tabsCollectionView.reloadData()
    }
  }

  var deselectedHeaderTextAttributes: [NSAttributedString.Key: Any] = [
    .foregroundColor: UIColor.gray,
    .font: UIFont.semibold14.dynamic,
  ] {
    didSet {
      tabsCollectionView.reloadData()
    }
  }

  var contentFrame: CGRect {
    safeAreaLayoutGuide.layoutFrame
  }

  override var tintColor: UIColor! {
    didSet {
      slidingView.backgroundColor = tintColor
    }
  }

  override init(frame: CGRect) {
    tabsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: tabsLayout)
    tabsContentCollectionView = UICollectionView(frame: .zero, collectionViewLayout: tabsContentLayout)
    super.init(frame: frame)
    configure()
  }

  required init?(coder aDecoder: NSCoder) {
    tabsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: tabsLayout)
    tabsContentCollectionView = UICollectionView(frame: .zero, collectionViewLayout: tabsContentLayout)
    super.init(coder: aDecoder)
    configure()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
      updateSelectedHeader()
    }
  }

  private func configure() {
    backgroundColor = .whitePrimary

    configureHeader()
    configureContent()

    addSubview(tabsContentCollectionView)
    addSubview(headerView)

    configureLayoutContraints()
  }

  private func configureHeader() {
    tabsLayout.scrollDirection = .horizontal
    tabsLayout.minimumLineSpacing = 0
    tabsLayout.minimumInteritemSpacing = 0

    tabsCollectionView.register(HeaderCell.self, forCellWithReuseIdentifier: CellId.header)
    tabsCollectionView.dataSource = self
    tabsCollectionView.delegate = self
    tabsCollectionView.backgroundColor = .clear

    slidingView.backgroundColor = tintColor
    slidingView.accessibilityIdentifier = "tab-selection-indicator"

    headerView.backgroundColor = barTintColor
    headerView.addSubview(tabsCollectionView)
    headerView.addSubview(slidingView)
    headerView.addSeparator(.bottom)
  }

  private func configureContent() {
    tabsContentLayout.scrollDirection = .horizontal
    tabsContentLayout.minimumLineSpacing = 0
    tabsContentLayout.minimumInteritemSpacing = 0

    tabsContentCollectionView.register(ContentCell.self, forCellWithReuseIdentifier: CellId.content)
    tabsContentCollectionView.dataSource = self
    tabsContentCollectionView.delegate = self
    tabsContentCollectionView.isPagingEnabled = true
    tabsContentCollectionView.bounces = false
    tabsContentCollectionView.showsVerticalScrollIndicator = false
    tabsContentCollectionView.showsHorizontalScrollIndicator = false
    tabsContentCollectionView.backgroundColor = .clear
  }

  private func configureLayoutContraints() {
    tabsCollectionView.translatesAutoresizingMaskIntoConstraints = false
    tabsContentCollectionView.translatesAutoresizingMaskIntoConstraints = false
    headerView.translatesAutoresizingMaskIntoConstraints = false
    slidingView.translatesAutoresizingMaskIntoConstraints = false

    headerView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
    headerView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
    headerView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor).isActive = true
    headerViewHeight = headerView.heightAnchor.constraint(equalToConstant: 46)
    headerViewHeight.isActive = true

    tabsContentCollectionView.leftAnchor.constraint(equalTo: safeAreaLayoutGuide.leftAnchor).isActive = true
    tabsContentCollectionView.rightAnchor.constraint(equalTo: safeAreaLayoutGuide.rightAnchor).isActive = true
    tabsContentCollectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor).isActive = true
    tabsContentCollectionView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor).isActive = true

    tabsCollectionView.leftAnchor.constraint(equalTo: headerView.leftAnchor).isActive = true
    tabsCollectionView.rightAnchor.constraint(equalTo: headerView.rightAnchor).isActive = true
    tabsCollectionView.topAnchor.constraint(equalTo: headerView.topAnchor).isActive = true
    tabsCollectionView.bottomAnchor.constraint(equalTo: slidingView.topAnchor).isActive = true

    slidingViewHeight = slidingView.heightAnchor.constraint(equalToConstant: 3)
    slidingViewHeight.isActive = true
    slidingView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor).isActive = true

    slidingViewLeft = slidingView.leftAnchor.constraint(equalTo: headerView.leftAnchor)
    slidingViewLeft.isActive = true
    slidingViewWidth = slidingView.widthAnchor.constraint(equalToConstant: 0)
    slidingViewWidth.isActive = true
  }

  private func updateTabBarVisibility() {
    headerView.isHidden = !showsTabBar
    headerViewHeight.constant = showsTabBar ? 46 : 0
    slidingViewHeight.constant = showsTabBar ? 3 : 0
    setNeedsLayout()
  }

  private func updateSelectedHeader() {
    tabsCollectionView.indexPathsForSelectedItems?.forEach {
      tabsCollectionView.deselectItem(at: $0, animated: false)
    }

    guard let selectedIndex,
          selectedIndex >= 0,
          tabsCollectionView.numberOfSections > 0,
          selectedIndex < tabsCollectionView.numberOfItems(inSection: 0) else {
      return
    }

    tabsCollectionView.selectItem(at: IndexPath(item: selectedIndex, section: 0),
                                  animated: false,
                                  scrollPosition: [])
    updateHeaderSelectionProgress()
  }

  private func headerSelectionProgress(for index: Int, selectedPosition: CGFloat) -> CGFloat {
    max(0, min(1, 1 - abs(CGFloat(index) - selectedPosition)))
  }

  private func currentSelectedPosition() -> CGFloat {
    let count = pageCount
    guard count > 1, tabsContentCollectionView.bounds.width > 0,
          hasContentItem(at: 0), hasContentItem(at: count - 1),
          let first = tabsContentCollectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)),
          let last = tabsContentCollectionView.layoutAttributesForItem(at: IndexPath(item: count - 1, section: 0)) else {
      return CGFloat(selectedIndex ?? 0)
    }
    // UIKit can mirror item order in RTL. Interpolate logical indices between
    // actual item centers instead of treating the leftmost physical page as item 0.
    let span = last.frame.midX - first.frame.midX
    guard span.isFinite, span != 0 else { return CGFloat(selectedIndex ?? 0) }
    let position = (tabsContentCollectionView.bounds.midX - first.frame.midX) / span * CGFloat(count - 1)
    guard position.isFinite else { return CGFloat(selectedIndex ?? 0) }
    return min(max(0, position), CGFloat(count - 1))
  }

  private func updateHeaderSelectionProgress() {
    let selectedPosition = currentSelectedPosition()
    for indexPath in tabsCollectionView.indexPathsForVisibleItems {
      guard let headerCell = tabsCollectionView.cellForItem(at: indexPath) as? HeaderCell else {
        continue
      }

      headerCell.updateSelectionProgress(headerSelectionProgress(for: indexPath.item,
                                                                 selectedPosition: selectedPosition))
    }
    updateSlidingIndicator(at: selectedPosition)
  }

  private func updateSlidingIndicator(at position: CGFloat) {
    guard pageCount > 0, contentFrame.width > 0,
          tabsContentCollectionView.bounds.width > 0, tabsContentCollectionView.bounds.height > 0,
          tabsCollectionView.bounds.width > 0 else {
      setSlidingIndicatorGeometry(left: 0, width: 0)
      return
    }
    guard position.isFinite,
          tabsCollectionView.numberOfSections > 0,
          tabsCollectionView.numberOfItems(inSection: 0) == pageCount else { return }
    let clampedPosition = min(max(0, position), CGFloat(pageCount - 1))
    let lower = Int(clampedPosition.rounded(.down))
    let upper = min(lower + 1, pageCount - 1)
    guard let first = headerItemFrame(at: lower), let last = headerItemFrame(at: upper) else { return }
    let progress = clampedPosition - CGFloat(lower)
    let left = first.minX + (last.minX - first.minX) * progress
    let width = first.width + (last.width - first.width) * progress
    guard left.isFinite, width.isFinite else { return }
    setSlidingIndicatorGeometry(left: left, width: width)
  }

  private func headerItemFrame(at index: Int) -> CGRect? {
    let path = IndexPath(item: index, section: 0)
    if let cell = tabsCollectionView.cellForItem(at: path) {
      // Convert the displayed cell through UIKit's hierarchy, including any RTL mirroring.
      return cell.convert(cell.bounds, to: headerView)
    }
    guard let attributes = tabsCollectionView.layoutAttributesForItem(at: path) else { return nil }
    return tabsCollectionView.convert(attributes.frame, to: headerView)
  }

  private func setSlidingIndicatorGeometry(left: CGFloat, width: CGFloat) {
    guard slidingViewWidth.constant != width || slidingViewLeft.constant != left else { return }
    slidingViewWidth.constant = width
    slidingViewLeft.constant = left
    // Both horizontal constraints belong to this header. Apply them in the same
    // pass as the item frames, rather than retaining the pre-resize indicator frame.
    headerView.setNeedsLayout()
    headerView.layoutIfNeeded()
  }

  func reloadData() {
    let count = pageCount
    let newIndex = count > 0 ? min(max(0, selectedIndex ?? 0), count - 1) : nil
    if selectedIndex != newIndex { selectedIndex = newIndex }
    lastContentSize = .zero
    tabsCollectionView.reloadData()
    tabsContentCollectionView.reloadData()
    setNeedsLayout()
  }

  private func hasContentItem(at index: Int) -> Bool {
    index >= 0 && index < pageCount && tabsContentCollectionView.numberOfSections > 0
      && index < tabsContentCollectionView.numberOfItems(inSection: 0)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let headerSize = tabsCollectionView.bounds.size
    if headerSize != lastHeaderSize {
      lastHeaderSize = headerSize
      tabsLayout.invalidateLayout()
      tabsCollectionView.layoutIfNeeded()
    }
    let contentSize = tabsContentCollectionView.bounds.size
    if contentSize != lastContentSize {
      // Record geometry before scrolling, which may synchronously trigger layout.
      lastContentSize = contentSize
      let invalidation = UICollectionViewFlowLayoutInvalidationContext()
      invalidation.invalidateFlowLayoutDelegateMetrics = true
      invalidation.invalidateFlowLayoutAttributes = true
      tabsContentLayout.invalidateLayout(with: invalidation)
      if contentSize.width > 0, contentSize.height > 0,
         !tabsContentCollectionView.isDragging, !tabsContentCollectionView.isDecelerating,
         let selectedIndex, hasContentItem(at: selectedIndex) {
        tabsContentCollectionView.layoutIfNeeded()
        tabsContentCollectionView.scrollToItem(at: IndexPath(item: selectedIndex, section: 0),
                                               at: .centeredHorizontally,
                                               animated: false)
      }
    }
    updateHeaderSelectionProgress()
  }
}

extension TabView: UICollectionViewDataSource {
  func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
    pageCount
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    var cell = UICollectionViewCell()
    if collectionView == tabsContentCollectionView {
      cell = collectionView.dequeueReusableCell(withReuseIdentifier: CellId.content, for: indexPath)
      if let contentCell = cell as? ContentCell {
        contentCell.view = dataSource?.tabView(self, viewAt: indexPath.item)
      }
    }

    if collectionView == tabsCollectionView {
      cell = collectionView.dequeueReusableCell(withReuseIdentifier: CellId.header, for: indexPath)
      if let headerCell = cell as? HeaderCell {
        let title = dataSource?.tabView(self, titleAt: indexPath.item) ?? ""
        headerCell.configureWith(selectedAttributes: selectedHeaderTextAttributes,
                                 deselectedAttributes: deselectedHeaderTextAttributes,
                                 text: title,
                                 selectionProgress: headerSelectionProgress(for: indexPath.item,
                                                                            selectedPosition: currentSelectedPosition()))
        if indexPath.item == selectedIndex {
          collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
      }
    }

    return cell
  }
}

extension TabView: UICollectionViewDelegateFlowLayout {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrollView == tabsContentCollectionView else {
      return
    }

    updateHeaderSelectionProgress()
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    guard scrollView == tabsContentCollectionView else {
      return
    }

    lastSelectedIndex = selectedIndex
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    guard scrollView == tabsContentCollectionView else {
      return
    }

    guard scrollView.bounds.width > 0, pageCount > 0 else { return }
    let position = currentSelectedPosition().rounded()
    guard position.isFinite, position >= 0, position < CGFloat(pageCount) else { return }
    selectedIndex = Int(position)
    if let selectedIndex = selectedIndex, selectedIndex != lastSelectedIndex {
      delegate?.tabView(self, didSelectTabAt: selectedIndex)
    }
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    if collectionView == tabsCollectionView {
      guard hasContentItem(at: indexPath.item) else { return }
      let isSelected = selectedIndex == indexPath.item
      if !isSelected {
        selectedIndex = indexPath.item
        tabsContentCollectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        delegate?.tabView(self, didSelectTabAt: selectedIndex!)
      }
    }
  }

  func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
    if collectionView == tabsCollectionView {
      collectionView.deselectItem(at: indexPath, animated: false)
    }
  }

  func collectionView(_ collectionView: UICollectionView,
                      layout _: UICollectionViewLayout,
                      sizeForItemAt _: IndexPath) -> CGSize {
    let bounds = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
    let size = CGSize(width: max(0, bounds.width), height: max(0, bounds.height))
    if collectionView == tabsContentCollectionView {
      return size
    } else {
      guard pageCount > 0 else { return .zero }
      return CGSize(width: size.width / CGFloat(pageCount), height: size.height)
    }
  }
}
