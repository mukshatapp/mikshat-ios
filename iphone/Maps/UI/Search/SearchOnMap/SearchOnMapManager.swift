@objc
protocol SearchOnMapManagerObserver: AnyObject {
  func searchManager(didChangeState state: SearchOnMapState)
}

private enum SearchOnMapMode {
  case normal
  case routing
  case routePointPicker
}

@objcMembers
final class SearchOnMapManager: NSObject {
  private var interactor: SearchOnMapInteractor? { viewController?.interactor }
  private let observers = ListenerContainer<SearchOnMapManagerObserver>()

  weak var viewController: SearchOnMapViewController?
  var isSearching: Bool { viewController != nil }
  private var mode: SearchOnMapMode = .normal
  private var isStarting = false
  private var didRecordMemoryWarning = false

  override init() {
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(didReceiveMemoryWarning),
                                           name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  // MARK: - Public methods

  func startSearching(isRouting: Bool) {
    guard !isStarting else { return }
    isStarting = true
    defer { isStarting = false }
    let mode: SearchOnMapMode
    if !isRouting {
      mode = .normal
    } else if MWMNavigationDashboardManager.shared().isRoutePointSelectionActive {
      mode = .routePointPicker
    } else {
      mode = .routing
    }
    if viewController != nil {
      if self.mode == mode {
        MikshatMemoryDiagnostics.logSearchPhase(.reuseScreen)
        interactor?.handle(.openSearch)
        MikshatMemoryDiagnostics.logSearchPhase(.openReturned)
        return
      }
      interactor?.closeForReplacement()
      viewController = nil
    }
    self.mode = mode
    didRecordMemoryWarning = false
    MikshatMemoryDiagnostics.logSearchPhase(.deactivateSelection)
    FrameworkHelper.deactivateMapSelection()
    MikshatMemoryDiagnostics.logSearchPhase(.constructScreen)
    let viewController = SearchOnMapViewControllerBuilder.build(mode: mode,
                                                                didChangeState: notifyObservers)
    self.viewController = viewController
    MikshatMemoryDiagnostics.logSearchPhase(.openReturned)
  }

  func hide() {
    interactor?.handle(.hideSearch)
  }

  func close() {
    if isSearching { MikshatMemoryDiagnostics.logSearchPhase(.closeRequested) }
    interactor?.handle(.closeSearch)
  }

  func setPlaceOnMapSelected(_ isSelected: Bool) {
    interactor?.handle(isSelected ? .didSelectPlaceOnMap : .didDeselectPlaceOnMap)
  }

  func setMapIsDragging() {
    interactor?.handle(.didStartDraggingMap)
  }

  func searchText(_ searchText: SearchQuery) {
    interactor?.handle(.didSelect(searchText))
  }

  func addObserver(_ observer: SearchOnMapManagerObserver) {
    observers.addListener(observer)
  }

  func removeObserver(_ observer: SearchOnMapManagerObserver) {
    observers.removeListener(observer)
  }

  private func notifyObservers(_ state: SearchOnMapState) {
    if state == .closed {
      MikshatMemoryDiagnostics.logSearchPhase(.closedState)
      viewController = nil
    }
    observers.forEach { observer in observer.searchManager(didChangeState: state) }
  }

  @objc private func didReceiveMemoryWarning() {
    guard isStarting || isSearching, !didRecordMemoryWarning else { return }
    didRecordMemoryWarning = true
    MikshatMemoryDiagnostics.logSearchPhase(.memoryWarning)
  }
}

private enum SearchOnMapViewControllerBuilder {
  static func build(mode: SearchOnMapMode,
                    didChangeState: @escaping ((SearchOnMapState) -> Void)) -> SearchOnMapViewController {
    let routePointSelector: RoutePointSelecting? = mode == .routePointPicker ? RoutePointSearchSelection() : nil
    let routePointActions = routePointSelector.map {
      SearchOnMap.ViewModel.RoutePointActions(title: $0.title,
                                              canSelectCurrentLocation: $0.canSelectCurrentLocation)
    }
    let viewController = SearchOnMapViewController()
    MikshatMemoryDiagnostics.logSearchPhase(.screenConstructed)
    let presenter = SearchOnMapPresenter(shouldHideForRouting: mode == .routing,
                                         routePointActions: routePointActions,
                                         didChangeState: didChangeState)
    let interactor = SearchOnMapInteractor(presenter: presenter,
                                           routePointSelector: routePointSelector,
                                           mapViewController: MapViewController.shared())
    MikshatMemoryDiagnostics.logSearchPhase(.observersRegistered)
    presenter.view = viewController
    viewController.interactor = interactor
    MikshatMemoryDiagnostics.logSearchPhase(.showScreen)
    viewController.show()
    MikshatMemoryDiagnostics.logSearchPhase(.showReturned)
    return viewController
  }
}
