class BottomTabBarViewController: UIViewController {
  var presenter: BottomTabBarPresenterProtocol!

  @IBOutlet var searchButton: MWMButton!
  @IBOutlet var helpButton: MWMButton!
  @IBOutlet var bookmarksButton: MWMButton!
  @IBOutlet var moreButton: MWMButton!
  @IBOutlet var downloadBadge: UIView!

  private var avaliableArea = CGRect.zero
  private var searchDiameterConstraints: [NSLayoutConstraint] = []
  private var searchCenterYConstraint: NSLayoutConstraint?
  private var searchCaptionGapConstraint: NSLayoutConstraint?
  private weak var mikshatSearchButton: UIButton?
  private var compactPhoneLayout: Bool?
  private struct ButtonLayoutDefaults {
    let button: UIButton
    let insets: NSDirectionalEdgeInsets
    let imagePadding: CGFloat
    let lineBreakMode: NSLineBreakMode
    let numberOfLines: Int
  }
  private var buttonLayoutDefaults: [ButtonLayoutDefaults] = []
  @objc var isHidden: Bool = false {
    didSet {
      updateFrame(animated: true)
    }
  }

  @objc var isApplicationBadgeHidden: Bool = true {
    didSet {
      updateBadge()
    }
  }

  @objc static var controller: BottomTabBarViewController? { MWMMapViewControlsManager.manager()?.tabBarController }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.alpha = 0 // Hide the view until it receives a first available area update.
    setupMikshatBar()
  }

  private func setupMikshatBar() {
    view.accessibilityIdentifier = "home.bottomBar"
    view.subviews.forEach { $0.isHidden = true }
    let stack = UIStackView()
    stack.accessibilityIdentifier = "home.bottomBar.content"
    stack.axis = .horizontal
    stack.distribution = .fillEqually
    stack.semanticContentAttribute = .forceLeftToRight
    stack.backgroundColor = MikshatStyle.cream
    stack.layer.cornerRadius = 27
    stack.layer.shadowColor = UIColor.black.cgColor
    stack.layer.shadowOpacity = 0.12
    stack.layer.shadowRadius = 8
    stack.layer.shadowOffset = CGSize(width: 0, height: 3)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let settings = MikshatStyle.button(L("settings"), symbol: "gearshape") {
      MapViewController.shared()?.navigationController?.pushViewController(SettingsBuilder.buildRoot(), animated: true)
    }
    let location = MikshatStyle.button(L("mikshat_save_share"), symbol: "mappin.circle") {
      guard let map = MapViewController.shared() else { return }
      MikshatLocationActions.presentMenu(from: map)
    }
    let search = MikshatStyle.button(L("search"), symbol: "magnifyingglass") { [weak self] in self?.presenter.onSearchButtonPressed() }
    mikshatSearchButton = search
    search.configuration?.baseForegroundColor = .white
    search.configuration?.background.backgroundColor = MikshatStyle.green
    search.configuration?.background.cornerRadius = 34
    search.configuration?.imagePadding = 6
    search.configuration?.title = nil
    let searchContainer = UIView()
    searchContainer.accessibilityIdentifier = "home.searchContainer"
    search.translatesAutoresizingMaskIntoConstraints = false
    let searchLabel = MikshatStyle.label(L("search"), size: 12, color: MikshatStyle.green)
    searchLabel.accessibilityIdentifier = "home.searchCaption"
    searchLabel.translatesAutoresizingMaskIntoConstraints = false
    searchContainer.addSubview(search)
    searchContainer.addSubview(searchLabel)
    searchDiameterConstraints = [search.widthAnchor.constraint(equalToConstant: 64),
                                 search.heightAnchor.constraint(equalToConstant: 64)]
    searchCenterYConstraint = search.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor, constant: -24)
    searchCaptionGapConstraint = searchLabel.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 5)
    NSLayoutConstraint.activate(searchDiameterConstraints + [
      search.centerXAnchor.constraint(equalTo: searchContainer.centerXAnchor),
      searchCenterYConstraint!,
      searchCaptionGapConstraint!,
      searchLabel.centerXAnchor.constraint(equalTo: searchContainer.centerXAnchor),
    ])
    let recording = MikshatStyle.button(L("mikshat_record_track"), symbol: "record.circle") {
      let recorder = TrackRecordingManager.shared
      if recorder.recordingState == .active {
        recorder.stopAndSave()
      } else {
        recorder.start { result in
          if case .failure = result { Toast.show(withText: L("mikshat_location_unavailable")) }
        }
      }
    }
    recording.configuration?.baseForegroundColor = TrackRecordingManager.shared.recordingState == .active ? .systemRed : .black
    TrackRecordingManager.shared.addObserver(self) { [weak recording] state, _, _ in
      recording?.configuration?.image = MikshatSymbols.image(named: "record.circle")
      recording?.configuration?.baseForegroundColor = state == .active ? .systemRed : .black
      recording?.accessibilityValue = L(state == .active ? "on" : "off")
    }
    let bookmarks = MikshatStyle.button(L("bookmarks"), symbol: "bookmark") { [weak self] in self?.presenter.onBookmarksButtonPressed() }
    for (button, name) in [(settings, "settings"), (location, "saveShare"),
                           (search, "search"), (recording, "record"), (bookmarks, "bookmarks")] {
      button.accessibilityIdentifier = "home." + name
      if let configuration = button.configuration, button !== search {
        buttonLayoutDefaults.append(ButtonLayoutDefaults(button: button,
                                                         insets: configuration.contentInsets,
                                                         imagePadding: configuration.imagePadding,
                                                         lineBreakMode: configuration.titleLineBreakMode,
                                                         numberOfLines: button.titleLabel?.numberOfLines ?? 1))
      }
    }
    for item in [settings, location, searchContainer, recording, bookmarks] { stack.addArrangedSubview(item) }
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: view.topAnchor, constant: -12),
      stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let viewport = view.superview?.bounds ?? view.bounds
    let compact = traitCollection.userInterfaceIdiom == .phone && viewport.width > viewport.height
    guard compactPhoneLayout != compact else { return }
    compactPhoneLayout = compact
    searchDiameterConstraints.forEach { $0.constant = compact ? 48 : 64 }
    searchCenterYConstraint?.constant = compact ? -10 : -24
    searchCaptionGapConstraint?.constant = compact ? 3 : 5
    mikshatSearchButton?.configuration?.background.cornerRadius = compact ? 24 : 34
    for defaults in buttonLayoutDefaults {
      guard var configuration = defaults.button.configuration else { continue }
      configuration.contentInsets = compact
        ? NSDirectionalEdgeInsets(top: 5, leading: 4, bottom: 5, trailing: 4) : defaults.insets
      configuration.imagePadding = compact ? 4 : defaults.imagePadding
      configuration.titleLineBreakMode = compact ? .byWordWrapping : defaults.lineBreakMode
      defaults.button.configuration = configuration
      defaults.button.titleLabel?.numberOfLines = compact ? 2 : defaults.numberOfLines
      defaults.button.titleLabel?.textAlignment = .center
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    presenter.viewWillAppear()
  }

  func updateAboutButtonIcon(isCrowdfunding: Bool) {
    let icon: ImageResource = isCrowdfunding ? .icCrowdfunding : (Settings.isNY() ? .icChristmasTree : .logo)
    helpButton.setImage(UIImage(resource: icon), for: .normal)
    updateBadge()
  }

  static func updateAvailableArea(_ frame: CGRect) {
    BottomTabBarViewController.controller?.updateAvailableArea(frame)
  }

  @IBAction func onSearchButtonPressed(_: Any) {
    presenter.onSearchButtonPressed()
  }

  @IBAction func onHelpButtonPressed(_: Any) {
    presenter.onHelpButtonPressed()
  }

  @IBAction func onBookmarksButtonPressed(_: Any) {
    presenter.onBookmarksButtonPressed()
  }

  @IBAction func onMenuButtonPressed(_: Any) {
    presenter.onMenuButtonPressed()
  }

  private func updateAvailableArea(_ frame: CGRect) {
    avaliableArea = frame
    updateFrame(animated: false)
    view.layoutIfNeeded()
  }

  private func updateFrame(animated: Bool) {
    if avaliableArea == .zero {
      return
    }
    let newFrame = CGRect(x: avaliableArea.minX,
                          y: isHidden ? avaliableArea.minY + avaliableArea.height : avaliableArea.minY,
                          width: avaliableArea.width,
                          height: avaliableArea.height)
    let alpha: CGFloat = isHidden ? 0 : 1
    if animated {
      UIView.animate(withDuration: AppConstants.defaultAnimationDuration,
                     delay: 0,
                     options: [.beginFromCurrentState],
                     animations: {
                       self.view.frame = newFrame
                       self.view.alpha = alpha
                     }, completion: nil)
    } else {
      view.frame = newFrame
      view.alpha = alpha
    }
  }

  private func updateBadge() {
    downloadBadge.isHidden = isApplicationBadgeHidden
  }
}
