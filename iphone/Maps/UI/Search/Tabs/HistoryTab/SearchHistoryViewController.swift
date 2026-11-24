protocol SearchHistoryViewControllerDelegate: UIScrollViewDelegate {
  func searchHistoryViewController(_ viewController: SearchHistoryViewController,
                                   didSelect entry: MikshatSearchHistoryEntry)
}

final class SearchHistoryViewController: MWMViewController {
  private weak var delegate: SearchHistoryViewControllerDelegate?
  private var entries: [MikshatSearchHistoryEntry] = []
  private let frameworkHelper: MWMSearchFrameworkHelper.Type
  private let emptyHistoryView = PlaceholderView(title: L("search_history_title"),
                                                 subtitle: L("search_history_text"))

  private let tableView = UITableView()

  // MARK: - Init

  init(frameworkHelper: MWMSearchFrameworkHelper.Type, delegate: SearchHistoryViewControllerDelegate?) {
    self.delegate = delegate
    self.frameworkHelper = frameworkHelper
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    setupTableView()
    setupNoResultsView()
    reload()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    reload()
  }

  // MARK: - Private methods

  private func setupTableView() {
    tableView.setStyle(.background)
    tableView.register(cell: SearchHistoryCell.self)
    tableView.keyboardDismissMode = .onDrag
    tableView.delegate = self
    tableView.dataSource = self
    tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 1))
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 60

    view.addSubview(tableView)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  private func setupNoResultsView() {
    view.addSubview(emptyHistoryView)
    emptyHistoryView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      emptyHistoryView.topAnchor.constraint(equalTo: view.topAnchor),
      emptyHistoryView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      emptyHistoryView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      emptyHistoryView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  private func showEmptyHistoryView(_ isVisible: Bool = true, animated: Bool = true) {
    UIView.transition(with: emptyHistoryView,
                      duration: animated ? AppConstants.defaultAnimationDuration : 0,
                      options: [.transitionCrossDissolve, .curveEaseInOut]) {
      self.emptyHistoryView.alpha = isVisible ? 1.0 : 0.0
      self.emptyHistoryView.isHidden = !isVisible
    }
  }

  private func clearSearchHistory() {
    frameworkHelper.clearSearchHistory()
    MikshatSearchLocations.clear()
    reload()
  }

  // MARK: - Public methods

  func reload() {
    guard isViewLoaded else { return }
    entries = MikshatSearchLocations.entries(queries: frameworkHelper.lastSearchQueries())
    showEmptyHistoryView(entries.isEmpty)
    tableView.reloadData()
  }
}

extension SearchHistoryViewController: UITableViewDataSource {
  func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
    entries.isEmpty ? 0 : entries.count + 1
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(cell: SearchHistoryCell.self, indexPath: indexPath)
    if indexPath.row == entries.count {
      cell.configure(for: .clear)
    } else {
      switch entries[indexPath.row] {
      case .location(let location): cell.configure(for: .location(location))
      case .unresolvedQuery(let query): cell.configure(for: .query(query))
      }
    }
    return cell
  }
}

extension SearchHistoryViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    if indexPath.row == entries.count {
      clearSearchHistory()
    } else {
      guard entries.indices.contains(indexPath.row) else { return }
      delegate?.searchHistoryViewController(self, didSelect: entries[indexPath.row])
    }
    tableView.deselectRow(at: indexPath, animated: true)
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    delegate?.scrollViewDidScroll?(scrollView)
  }

  func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
    delegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
  }
}

extension SearchHistoryViewController: ModallyPresentedViewController {
  func presentationFrameDidChange(_ frame: CGRect) {
    guard isViewLoaded else { return }
    tableView.contentInset.bottom = frame.origin.y
    emptyHistoryView.presentationFrameDidChange(frame)
  }
}
