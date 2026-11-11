@objc
protocol SearchTabViewControllerDelegate: UIScrollViewDelegate {
  func searchTabController(_ viewController: SearchTabViewController, didSearch: SearchQuery)
}

@objc
final class SearchTabViewController: MWMViewController {
  private static let selectedIndexKey = "SearchTabViewController_selectedIndexKey"
  private let frameworkHelper: MWMSearchFrameworkHelper.Type
  private let userDefaults: UserDefaults
  private lazy var historyViewController = SearchHistoryViewController(frameworkHelper: frameworkHelper,
                                                                       delegate: self)

  @objc weak var delegate: SearchTabViewControllerDelegate?

  init(frameworkHelper: MWMSearchFrameworkHelper.Type = MWMSearchFrameworkHelper.self,
       userDefaults: UserDefaults = .standard) {
    self.frameworkHelper = frameworkHelper
    self.userDefaults = userDefaults
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    // Older builds persisted Categories as page 1. History is now displayed
    // directly, so normalize old and out-of-range values to its sole index.
    userDefaults.set(0, forKey: Self.selectedIndexKey)
    addChild(historyViewController)
    let historyView = historyViewController.view!
    historyView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(historyView)
    NSLayoutConstraint.activate([
      historyView.topAnchor.constraint(equalTo: view.topAnchor),
      historyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      historyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      historyView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    historyViewController.didMove(toParent: self)
  }

  func reloadSearchHistory() {
    historyViewController.reload()
  }
}

extension SearchTabViewController: ModallyPresentedViewController {
  func presentationFrameDidChange(_ frame: CGRect) {
    historyViewController.presentationFrameDidChange(frame)
  }
}

extension SearchTabViewController: UIScrollViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    delegate?.scrollViewDidScroll?(scrollView)
  }

  func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
    delegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
  }
}

extension SearchTabViewController: SearchHistoryViewControllerDelegate {
  func searchHistoryViewController(_: SearchHistoryViewController,
                                   didSelect query: String) {
    let query = SearchQuery(query.trimmingCharacters(in: .whitespacesAndNewlines) + " ", source: .history)
    delegate?.searchTabController(self, didSearch: query)
  }
}
