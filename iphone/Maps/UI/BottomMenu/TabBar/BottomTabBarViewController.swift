class BottomTabBarViewController: UIViewController {
  var presenter: BottomTabBarPresenterProtocol!

  @IBOutlet var searchButton: MWMButton!
  @IBOutlet var helpButton: MWMButton!
  @IBOutlet var bookmarksButton: MWMButton!
  @IBOutlet var moreButton: MWMButton!
  @IBOutlet var downloadBadge: UIView!

  private var avaliableArea = CGRect.zero
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
    view.subviews.forEach { $0.isHidden = true }
    let stack = UIStackView()
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
    let location = MikshatStyle.button(L("mikshat_my_location"), symbol: "mappin.circle") {
      LocationManager.start()
      LocationManager.setMyPositionMode(.follow)
    }
    let search = MikshatStyle.button(L("search"), symbol: "magnifyingglass") { [weak self] in self?.presenter.onSearchButtonPressed() }
    search.configuration?.baseForegroundColor = .white
    search.configuration?.background.backgroundColor = MikshatStyle.green
    search.configuration?.background.cornerRadius = 34
    search.configuration?.imagePadding = 6
    search.configuration?.title = nil
    let searchContainer = UIView()
    search.translatesAutoresizingMaskIntoConstraints = false
    let searchLabel = MikshatStyle.label(L("search"), size: 12, color: MikshatStyle.green)
    searchLabel.translatesAutoresizingMaskIntoConstraints = false
    searchContainer.addSubview(search)
    searchContainer.addSubview(searchLabel)
    NSLayoutConstraint.activate([
      search.widthAnchor.constraint(equalToConstant: 64), search.heightAnchor.constraint(equalToConstant: 64),
      search.centerXAnchor.constraint(equalTo: searchContainer.centerXAnchor),
      search.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor, constant: -24),
      searchLabel.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 5),
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
    recording.configuration?.baseForegroundColor = .systemRed
    TrackRecordingManager.shared.addObserver(self) { [weak recording] state, _, _ in
      recording?.configuration?.image = UIImage(systemName: state == .active ? "stop.circle.fill" : "record.circle")
      recording?.accessibilityValue = L(state == .active ? "on" : "off")
    }
    let bookmarks = MikshatStyle.button(L("bookmarks"), symbol: "bookmark") { [weak self] in self?.presenter.onBookmarksButtonPressed() }
    for item in [settings, location, searchContainer, recording, bookmarks] { stack.addArrangedSubview(item) }
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: view.topAnchor, constant: -12),
      stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
    ])
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
