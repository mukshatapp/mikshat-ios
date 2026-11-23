protocol PlacePageViewProtocol: AnyObject {
  var interactor: PlacePageInteractorProtocol? { get set }
  var view: UIView! { get }

  func showNextStop()
  func scrollToReveal(_ anchor: UIView)
  func layoutIfNeeded()
  func refreshContentSize()
  func updateWithLayout(_ layout: IPlacePageLayout)
  func showAlert(_ alert: UIAlertController)
}

final class PlacePageScrollView: UIScrollView {
  override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
    point.y > 0
  }

  override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
    guard isScrollEnabled else { return }
    super.scrollRectToVisible(rect, animated: animated)
  }
}

@objc final class PlacePageViewController: UIViewController {
  private enum Constants {
    static let actionBarHeight: CGFloat = 50
    static let additionalPreviewOffset: CGFloat = 80
    static let additionalRevealOffset: CGFloat = 12
    static let fastSwipeDownVelocity: CGFloat = -3.0
    static let fastSwipeUpVelocity: CGFloat = 2.0
  }

  @IBOutlet private var scrollView: PlacePageScrollView!
  @IBOutlet private var stackView: UIStackView!
  @IBOutlet private var actionBarContainerView: UIView!
  @IBOutlet private var actionBarHeightConstraint: NSLayoutConstraint!
  @IBOutlet private var panGesture: UIPanGestureRecognizer!

  private let headerStackView = UIStackView()
  private let backgroundView = UIView()
  private var beginDragging = false
  private var previousTraitCollection: UITraitCollection?
  private var scrollSteps: [PlacePageState] = []
  private var currentScrollContentOffset: CGPoint?
  private var previousScrollContentOffset: CGPoint?
  private var userDefinedStep: PlacePageState?
  private var isNavigationBarVisible = false
  private var isFirstOpening = true
  private var isVisible: Bool = false
  private var closingAnimator: UIViewPropertyAnimator?
  private var previousLayoutSize: CGSize?
  private var scrollingAnimator: UIViewPropertyAnimator?
  private var isChangingSize = false
  private var sizeTransitionRevision: UInt = 0
  private var isContentSizeRefreshScheduled = false

  var layout: IPlacePageLayout!
  var interactor: PlacePageInteractorProtocol?
  var isPreviewPlus: Bool = false

  // MARK: - VC Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()

    MWMKeyboard.add(self)

    setupView()
    setupLayout(layout)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard !layout.headerViewController.isEditingTitle else { return }
    // Every device now presents a bottom sheet; the old tablet sidebar's
    // horizontal-dismiss gesture must not move an Auto Layout constrained sheet.
    panGesture.isEnabled = false
    previousTraitCollection = traitCollection
    updateBackgroundViewFrame()
    let size = view.bounds.size
    if let previousLayoutSize, previousLayoutSize != size, isVisible {
      scheduleContentSizeRefresh()
    }
    previousLayoutSize = size
  }

  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    // UIKit owns this geometry animation. Starting another sheet animator for
    // each intermediate height feeds scroll insets/offsets back into its layout.
    sizeTransitionRevision &+= 1
    let revision = sizeTransitionRevision
    isChangingSize = true
    stopScrollingAnimation()
    super.viewWillTransition(to: size, with: coordinator)
    let completion: (UIViewControllerTransitionCoordinatorContext) -> Void = { [weak self] _ in
      self?.finishSizeTransition(revision: revision)
    }
    if !coordinator.animate(alongsideTransition: nil, completion: completion) {
      DispatchQueue.main.async { [weak self] in
        self?.finishSizeTransition(revision: revision)
      }
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    isVisible = true
    updatePreviewOffset()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    currentScrollContentOffset = scrollView.contentOffset
    isVisible = false
    stopScrollingAnimation()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard isViewLoaded, layout != nil else { return }
    if let previousTraitCollection,
       previousTraitCollection.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory ||
        previousTraitCollection.verticalSizeClass != traitCollection.verticalSizeClass {
      scheduleContentSizeRefresh()
    }
  }

  // MARK: - Actions

  @IBAction func onPan(gesture: UIPanGestureRecognizer) {
    let xOffset = gesture.translation(in: view.superview).x
    gesture.setTranslation(CGPoint.zero, in: view.superview)
    view.minX += xOffset
    view.minX = min(view.minX, 0)
    let alpha = view.maxX / view.width
    view.alpha = alpha

    let state = gesture.state
    if state == .ended || state == .cancelled {
      if alpha < 0.8 {
        interactor?.close()
      } else {
        UIView.animate(withDuration: AppConstants.defaultAnimationDuration) {
          self.view.minX = 0
          self.view.alpha = 1
        }
      }
    }
  }

  // MARK: - Private methods

  private func finishSizeTransition(revision: UInt) {
    // A reversal can start a new transition before the previous coordinator's
    // completion or unregistered-animation fallback reaches the main queue.
    guard revision == sizeTransitionRevision else { return }
    isChangingSize = false
    scheduleContentSizeRefresh()
  }

  private func scheduleContentSizeRefresh() {
    guard !isChangingSize, !isContentSizeRefreshScheduled else { return }
    isContentSizeRefreshScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isContentSizeRefreshScheduled = false
      guard self.isVisible, self.viewIfLoaded?.window != nil, !self.isChangingSize,
            self.closingAnimator == nil, self.layout != nil else { return }
      if self.layout.headerViewController.isEditingTitle {
        self.updateContentOffsetForTitleEditing()
      } else {
        // Reflow the settled viewport once; only explicit sheet interactions
        // animate their offset, independently of system geometry transitions.
        self.refreshContentSize(animated: false)
      }
    }
  }

  private func stopScrollingAnimation() {
    if let scrollingAnimator, scrollingAnimator.state == .active {
      scrollingAnimator.stopAnimation(true)
    }
    scrollingAnimator = nil
  }

  private func updateSteps() {
    layoutIfNeeded()
    // viewDidLoad still has the storyboard's size. Use the laid-out viewport
    // before calculating any negative offset, including the first tablet open.
    if scrollView.contentInset.top != scrollView.height {
      scrollView.contentInset.top = scrollView.height
    }
    updateBackgroundViewFrame()
    scrollSteps = layout.calculateSteps(inScrollView: scrollView,
                                        compact: traitCollection.verticalSizeClass == .compact)
  }

  private func findNextStop(_ offset: CGFloat, velocity: CGFloat) -> PlacePageState {
    if velocity == 0 {
      return findNearestStop(offset)
    }

    var result: PlacePageState
    if velocity < 0 {
      guard let first = scrollSteps.first else { return .closed(-scrollView.height) }
      result = first
      for item in scrollSteps.suffix(from: 1) {
        if offset > boundedOffset(for: item) {
          result = item
        }
      }
    } else {
      guard let last = scrollSteps.last else { return .closed(-scrollView.height) }
      result = last
      for item in scrollSteps.reversed().suffix(from: 1) {
        if offset < boundedOffset(for: item) {
          result = item
        }
      }
    }

    return result
  }

  private func setupView() {
    view.accessibilityIdentifier = "placePage.sheet"
    scrollView.accessibilityIdentifier = "placePage.scroll"
    stackView.accessibilityIdentifier = "placePage.content"
    headerStackView.accessibilityIdentifier = "placePage.header"
    backgroundView.accessibilityIdentifier = "placePage.background"
    actionBarContainerView.accessibilityIdentifier = "placePage.actions"
    view.insertSubview(backgroundView, at: 0)
    backgroundView.setStyle(.ppBackgroundView)

    scrollView.decelerationRate = .fast
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.setStyle(.ppView)

    headerStackView.axis = .vertical
    headerStackView.distribution = .fill

    stackView.backgroundColor = .clear

    if isiPad {
      let bottomCorners: CACornerMask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
      actionBarContainerView.layer.setCornerRadius(.modalSheet, maskedCorners: bottomCorners)
      actionBarContainerView.layer.masksToBounds = true
    }

    if previousTraitCollection == nil {
      scrollView.contentInset = UIEdgeInsets(top: view.height, left: 0, bottom: 0, right: 0)
      scrollView.layoutIfNeeded()
    }
  }

  private func setupLayout(_ layout: IPlacePageLayout) {
    let showSeparator = layout.sectionSpacing > 0
    stackView.spacing = layout.sectionSpacing
    fillHeader(with: layout.headerViewControllers, showSeparator: showSeparator)
    fillBody(with: layout.bodyViewControllers, showSeparator: showSeparator)

    layout.headerViewController.didStartEditingTitle = { [weak self] isEditing in
      self?.scrollView.isScrollEnabled = !isEditing
    }
    layout.headerViewController.didChangeEditedTitle = { [weak self] in
      self?.updateContentOffsetForTitleEditing()
    }

    scrollView.isScrollEnabled = true
    // Keep only an active drag: its release re-targets with the new steps.
    // isDragging alone stays true while decelerating.
    beginDragging = scrollView.isTracking && scrollView.isDragging
    if let actionBar = layout.actionBar {
      hideActionBar(false)
      addActionBar(actionBar)
    } else {
      hideActionBar(true)
    }
  }

  private func fillHeader(with viewControllers: [UIViewController], showSeparator: Bool = true) {
    viewControllers.forEach { [self] viewController in
      if !stackView.arrangedSubviews.contains(headerStackView) {
        stackView.addArrangedSubview(headerStackView)
      }
      // Header/preview contents size themselves against their root bounds. A
      // nested safe-area guide here would include the offscreen scroll offset
      // in the child's intrinsic height and feed that height back into layout.
      addChild(viewController)
      headerStackView.addArrangedSubview(viewController.view)
      viewController.didMove(toParent: self)
    }
    if showSeparator {
      headerStackView.addSeparator(.bottom)
    }
  }

  private func fillBody(with viewControllers: [UIViewController], showSeparator: Bool = true) {
    viewControllers.forEach { [self] viewController in
      addChild(viewController)
      stackView.addArrangedSubview(viewController.view)
      viewController.didMove(toParent: self)
      if showSeparator {
        viewController.view.addSeparator(.top)
        viewController.view.addSeparator(.bottom)
      }
    }
  }

  private func cleanupLayout() {
    guard let layout else { return }
    let childViewControllers = [layout.actionBar, layout.navigationBar] + layout.headerViewControllers + layout.bodyViewControllers
    for childViewController in childViewControllers {
      childViewController?.willMove(toParent: nil)
      childViewController?.view.removeFromSuperview()
      childViewController?.removeFromParent()
    }
    headerStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
  }

  private func findNearestStop(_ offset: CGFloat) -> PlacePageState {
    var result = scrollSteps[0]
    for ppState in scrollSteps.suffix(from: 1) {
      if abs(boundedOffset(for: result) - offset) > abs(boundedOffset(for: ppState) - offset) {
        result = ppState
      }
    }
    return result
  }

  private func boundedOffset(for step: PlacePageState) -> CGFloat {
    min(scrollView.contentSize.height - scrollView.height, step.offset)
  }

  private func addActionBar(_ actionBarViewController: UIViewController) {
    addChild(actionBarViewController)
    actionBarViewController.view.translatesAutoresizingMaskIntoConstraints = false
    actionBarContainerView.addSubview(actionBarViewController.view)
    actionBarViewController.didMove(toParent: self)
    NSLayoutConstraint.activate([
      actionBarViewController.view.leadingAnchor.constraint(equalTo: actionBarContainerView.leadingAnchor),
      actionBarViewController.view.topAnchor.constraint(equalTo: actionBarContainerView.topAnchor),
      actionBarViewController.view.trailingAnchor.constraint(equalTo: actionBarContainerView.trailingAnchor),
      actionBarViewController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
    ])
  }

  private func addNavigationBar(_ header: UIViewController) {
    header.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header.view)
    addChild(header)
    NSLayoutConstraint.activate([
      header.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      header.view.topAnchor.constraint(equalTo: view.topAnchor),
      header.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  private func scrollTo(_ point: CGPoint, animated: Bool = true, forced: Bool = false, completion: (() -> Void)? = nil) {
    if beginDragging, !forced {
      return
    }
    stopScrollingAnimation()
    let contentOffset = CGPoint(x: point.x, y: min(scrollView.contentSize.height - scrollView.height, point.y))
    let bound = view.bounds.height + contentOffset.y
    if animated {
      if isFirstOpening {
        updateTopBound(bound)
        isFirstOpening = false
      }
      scrollingAnimator = ModalPresentationAnimator.animate(animations: { [weak self] in
        guard let self else { return }
        self.scrollView.contentOffset = contentOffset
        self.updateBackgroundViewFrame()
        self.layoutIfNeeded()
      }, completion: { [weak self] complete in
        self?.scrollingAnimator = nil
        if complete {
          completion?()
        }
      })
    } else {
      scrollView?.contentOffset = contentOffset
      updateTopBound(bound)
      updateBackgroundViewFrame()
      completion?()
    }
  }

  private func showLastStop() {
    if let lastStop = scrollSteps.last {
      scrollTo(CGPoint(x: 0, y: lastStop.offset), forced: true)
      userDefinedStep = lastStop
    }
  }

  private func updateTopBound(_ bound: CGFloat, updatingViewport: Bool = true) {
    let isCompactPhone = !isiPad && traitCollection.verticalSizeClass == .compact
    let insets = UIEdgeInsets(top: 0, left: 0, bottom: isCompactPhone ? 0 : bound, right: 0)
    interactor?.updateVisibleAreaInsets(insets, updatingViewport: updatingViewport)
  }

  private func updateBackgroundViewFrame() {
    backgroundView.frame = CGRect(x: 0,
                                  y: max(scrollView.origin.y, -scrollView.contentOffset.y),
                                  width: scrollView.width,
                                  height: stackView.height + actionBarContainerView.height)
  }
}

// MARK: - PlacePageViewProtocol

extension PlacePageViewController: PlacePageViewProtocol {
  func layoutIfNeeded() {
    guard layout != nil else { return }
    view.layoutIfNeeded()
  }

  func refreshContentSize() {
    refreshContentSize(animated: !UIAccessibility.isReduceMotionEnabled)
  }

  private func refreshContentSize(animated: Bool) {
    guard layout != nil, isViewLoaded, !isChangingSize, closingAnimator == nil else { return }
    let oldOffset = scrollView.contentOffset.y
    let oldPreviewOffset = scrollSteps.first { if case .preview = $0 { return true }; return false }?.offset
    let wasAtFullStop = scrollSteps.last.map { abs(oldOffset - boundedOffset(for: $0)) < 1 } ?? false
    let topInset = scrollView.height
    if scrollView.contentInset.top != topInset { scrollView.contentInset.top = topInset }
    updateSteps()
    guard isVisible, !beginDragging, !layout.headerViewController.isEditingTitle else { return }

    let previewOffset = scrollSteps.first { if case .preview = $0 { return true }; return false }?.offset
    let fullOffset = scrollSteps.last.map { boundedOffset(for: $0) } ?? oldOffset
    var targetOffset = oldOffset
    switch userDefinedStep {
    case .preview:
      targetOffset = previewOffset ?? oldOffset
    case .previewPlus:
      targetOffset = scrollSteps.first { if case .previewPlus = $0 { return true }; return false }?.offset ?? fullOffset
    case .full:
      targetOffset = wasAtFullStop ? fullOffset : oldOffset
    case .closed:
      return
    case nil:
      if wasAtFullStop {
        targetOffset = fullOffset
      } else if let previewOffset, let oldPreviewOffset {
        targetOffset += previewOffset - oldPreviewOffset
      }
    }
    scrollTo(CGPoint(x: 0, y: targetOffset), animated: animated)
  }

  func updateWithLayout(_ layout: IPlacePageLayout) {
    currentScrollContentOffset = scrollView.contentOffset
    cleanupLayout()
    self.layout = layout
    setupLayout(layout)
    updatePreviewOffset()
  }

  private func hideActionBar(_ value: Bool) {
    actionBarHeightConstraint.constant = !value ? Constants.actionBarHeight : .zero
  }

  func updatePreviewOffset() {
    updateSteps()
    guard !beginDragging, isVisible else { return }
    let previewOffset = scrollSteps.first { if case .preview = $0 { return true }; return false }?.offset ?? scrollSteps.last?.offset ?? 0
    let previewPlusOffset = scrollSteps.first { if case .previewPlus = $0 { return true }; return false }?.offset
    let estimatedYOffset = isPreviewPlus ? previewPlusOffset ?? previewOffset : previewOffset + Constants.additionalPreviewOffset
    var offset = CGPoint(x: 0, y: estimatedYOffset)
    if let userDefinedStep {
      // Respect user defined offset if possible.
      switch userDefinedStep {
      case .preview:
        offset.y = previewOffset
      case .previewPlus:
        offset.y = previewPlusOffset ?? previewOffset
      case .full:
        offset.y = currentScrollContentOffset?.y ?? scrollSteps.last?.offset ?? 0
      case .closed:
        break
      }
    } else if let currentScrollContentOffset {
      // Keep previous offset during layout update if possible.
      offset.y = max(estimatedYOffset, currentScrollContentOffset.y)
    }
    scrollTo(offset)
  }

  func showNextStop() {
    guard scrollView.isScrollEnabled else { return }
    if let nextStop = scrollSteps.last(where: { boundedOffset(for: $0) > scrollView.contentOffset.y }) {
      scrollTo(CGPoint(x: 0, y: nextStop.offset), forced: true)
    }
  }

  func scrollToReveal(_ anchor: UIView) {
    guard scrollView.isScrollEnabled else { return }
    let bottomY = scrollView.convert(anchor.bounds, from: anchor).maxY
    let offset = CGPoint(x: 0, y: bottomY - scrollView.height + Constants.additionalRevealOffset)
    scrollTo(offset, forced: true)
  }

  @objc
  func close(completion: @escaping (() -> Void)) {
    // The completion removes the current Place Page, so it must run only once.
    guard closingAnimator?.state != .active else { return }
    stopScrollingAnimation()
    view.isUserInteractionEnabled = false
    updateTopBound(.zero)
    closingAnimator = ModalPresentationAnimator.animate(
      animations: {
        // Moving the full-height controller offscreen changes its inherited
        // safe area while expanded child views are self-sizing. Fade the sheet
        // with fixed geometry, as the existing tablet dismissal already did.
        self.view.alpha = 0
      },
      completion: { _ in
        self.closingAnimator = nil
        self.interactor?.didClose()
        self.interactor = nil
        MWMKeyboard.remove(self)
        completion()
      }
    )
  }

  @objc
  func finishClosingIfNeeded() {
    guard let closingAnimator, closingAnimator.state == .active else { return }
    closingAnimator.stopAnimation(false)
    closingAnimator.finishAnimation(at: .end)
  }

  func showAlert(_ alert: UIAlertController) {
    present(alert, animated: true)
  }
}

// MARK: - UIScrollViewDelegate

extension PlacePageViewController: UIScrollViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    currentScrollContentOffset = scrollView.contentOffset
    guard !isChangingSize else {
      updateBackgroundViewFrame()
      return
    }

    if scrollView.contentOffset.y < -scrollView.height + 1, beginDragging, !layout.headerViewController.isEditingTitle {
      interactor?.close()
    }
    let bound = view.height + scrollView.contentOffset.y
    updateTopBound(bound, updatingViewport: false) // Skip updating viewport on every drag.
    onOffsetChanged(scrollView.contentOffset.y)
    updateBackgroundViewFrame()
  }

  func scrollViewWillBeginDragging(_: UIScrollView) {
    beginDragging = true
  }

  func scrollViewDidEndDragging(_: UIScrollView, willDecelerate _: Bool) {
    beginDragging = false
  }

  func scrollViewDidEndDecelerating(_: UIScrollView) {
    beginDragging = false
  }

  func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                 withVelocity velocity: CGPoint,
                                 targetContentOffset: UnsafeMutablePointer<CGPoint>) {
    if velocity.y < Constants.fastSwipeDownVelocity {
      interactor?.close()
      return
    }

    guard let lastStop = scrollSteps.last else { return }
    targetContentOffset.pointee.y = min(scrollView.contentSize.height - scrollView.height,
                                      targetContentOffset.pointee.y)
    let isFullyExpanded = isNavigationBarVisible || scrollView.contentOffset.y >= boundedOffset(for: lastStop)

    if velocity.y > Constants.fastSwipeUpVelocity, !isFullyExpanded {
      showLastStop()
      return
    }

    if targetContentOffset.pointee.y > lastStop.offset {
      return
    }

    let nextStep = findNextStop(scrollView.contentOffset.y, velocity: velocity.y)
    if case .closed = nextStep, !layout.headerViewController.isEditingTitle {
      targetContentOffset.pointee = scrollView.contentOffset
      interactor?.close()
      return
    }
    targetContentOffset.pointee = CGPoint(x: 0, y: boundedOffset(for: nextStep))
    userDefinedStep = nextStep
  }

  private func onOffsetChanged(_ offset: CGFloat) {
    if offset > 0, !isNavigationBarVisible {
      setNavigationBarVisible(true)
    } else if offset <= 0, isNavigationBarVisible {
      setNavigationBarVisible(false)
    }
  }

  private func setNavigationBarVisible(_ visible: Bool) {
    guard visible != isNavigationBarVisible, let navigationBar = layout?.navigationBar else { return }
    isNavigationBarVisible = visible
    if isNavigationBarVisible {
      addNavigationBar(navigationBar)
    } else {
      navigationBar.removeFromParent()
      navigationBar.view.removeFromSuperview()
    }
  }

  private func updateContentOffsetForTitleEditing() {
    let keyboardHeight = MWMKeyboard.keyboardHeight()
    var yOffset: CGFloat?
    if keyboardHeight > 0 {
      let yOffsetFromKeyboard = layout.headerViewController.view.height
      let visibleScrollHeight = scrollView.frame.height + actionBarContainerView.frame.height - keyboardHeight
      yOffset = yOffsetFromKeyboard - visibleScrollHeight
      if previousScrollContentOffset == nil {
        previousScrollContentOffset = scrollView.contentOffset
      }
    } else if let previousScrollContentOffset {
      yOffset = previousScrollContentOffset.y
      self.previousScrollContentOffset = nil
    }

    guard let yOffset else { return }

    let bottomInset = max(0, keyboardHeight - actionBarContainerView.frame.height)
    scrollView.contentInset.bottom = bottomInset

    let minOffset = -scrollView.adjustedContentInset.top
    let maxOffset = max(minOffset, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.height)
    let contentOffset = CGPoint(x: 0, y: min(maxOffset, max(minOffset, yOffset)))
    scrollView.contentOffset = contentOffset
    currentScrollContentOffset = contentOffset
    updateBackgroundViewFrame()
  }
}

// MARK: - MWMKeyboardObserver

extension PlacePageViewController: MWMKeyboardObserver {
  func onKeyboardWillAnimate() {}

  func onKeyboardAnimation() {
    guard isVisible else { return }
    updateContentOffsetForTitleEditing()
  }
}
