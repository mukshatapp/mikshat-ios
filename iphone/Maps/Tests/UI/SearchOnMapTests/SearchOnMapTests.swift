@testable import Organic_Maps__Debug_
import XCTest
import CoreLocation

final class SearchOnMapTests: XCTestCase {
  private var presenter: SearchOnMapPresenter!
  private var interactor: SearchOnMapInteractor!
  private var view: SearchOnMapViewMock!
  private var searchManager: SearchManagerMock.Type!
  private var routePointSelector: RoutePointSelectorMock!
  private var currentState: SearchOnMapState = .searching
  private var openedHistoryCoordinate: CLLocationCoordinate2D?
  private var openedHistoryTitle: String?
  private var previousSavedLocations: Any?
  private var previousLegacyLocations: Any?
  private var previousHistoryEnabled = true

  override func setUp() {
    super.setUp()
    previousHistoryEnabled = Settings.searchHistoryEnabled()
    previousSavedLocations = UserDefaults.standard.object(forKey: MikshatSearchHistoryStore.storageKey)
    previousLegacyLocations = UserDefaults.standard.object(forKey: "mikshat_search_locations")
    Settings.setSearchHistoryEnabled(true)
    MikshatSearchLocations.clear()
    openedHistoryCoordinate = nil
    openedHistoryTitle = nil
    searchManager = SearchManagerMock.self
    presenter = SearchOnMapPresenter(shouldHideForRouting: false,
                                     didChangeState: { [weak self] in self?.currentState = $0 })
    interactor = SearchOnMapInteractor(presenter: presenter, searchManager: searchManager,
                                        showHistoryLocation: { [weak self] coordinate, title in
                                          self?.openedHistoryCoordinate = coordinate
                                          self?.openedHistoryTitle = title
                                        })
    view = SearchOnMapViewMock()
    presenter.view = view
  }

  override func tearDown() {
    presenter = nil
    interactor = nil
    view = nil
    searchManager.results = .empty
    searchManager.setSearchMode(.everywhere)
    searchManager.updateViewportCallsCount = 0
    searchManager.showResultCallCount = 0
    searchManager.clearCallCount = 0
    searchManager.searchQueryCallCount = 0
    searchManager.savedQueries = []
    Settings.setSearchHistoryEnabled(previousHistoryEnabled)
    UserDefaults.standard.set(previousSavedLocations, forKey: MikshatSearchHistoryStore.storageKey)
    UserDefaults.standard.set(previousLegacyLocations, forKey: "mikshat_search_locations")
    routePointSelector = nil
    searchManager = nil
    super.tearDown()
  }

  func test_GivenViewIsLoading_WhenViewLoads_ThenShowsHistoryAndCategory() {
    interactor.handle(.openSearch)

    XCTAssertEqual(currentState, .searching)
    XCTAssertEqual(view.viewModel.presentationStep, .expanded)
    XCTAssertEqual(view.viewModel.contentState, .historyAndCategory)
    XCTAssertEqual(view.viewModel.searchingText, nil)
    XCTAssertEqual(view.viewModel.isTyping, true)
  }

  func test_GivenSavedHistoryPoint_WhenSelected_ThenOpensItWithoutSearchingOrUsingAResultIndex() {
    interactor.handle(.openSearch)
    let location = MikshatSearchLocation(id: "saved", title: "Same name", subtitle: "Selected region", query: "broad query",
                                         latitude: 26.2317, longitude: 44.9453)
    interactor.handle(.didSelect(SearchQuery(historyLocation: location)))
    XCTAssertEqual(openedHistoryCoordinate?.latitude, location.latitude)
    XCTAssertEqual(openedHistoryCoordinate?.longitude, location.longitude)
    XCTAssertEqual(openedHistoryTitle, location.title)
    XCTAssertEqual(searchManager.searchQueryCallCount, 0)
    XCTAssertEqual(searchManager.showResultCallCount, 0)
    XCTAssertTrue(searchManager.savedQueries.isEmpty)
    XCTAssertEqual(view.closeCallCount, 1)
    XCTAssertEqual(currentState, .closed)
    let renderCount = view.renderCallCount
    searchManager.results = SearchResult.stubResults()
    XCTAssertEqual(view.renderCallCount, renderCount, "Late search results cannot replace the selected saved point")
  }

  func test_GivenLegacyHistoryQuery_WhenResultIsChosen_ThenLaterTapOpensThatPointWithoutSearchingAgain() throws {
    interactor.handle(.openSearch)
    let result = SearchLocationResultStub()
    let query = SearchQuery("broad query", source: .history)
    interactor.handle(.didSelect(query))
    XCTAssertEqual(searchManager.searchQueryCallCount, 1)
    XCTAssertTrue(MikshatSearchHistoryStore().locations.isEmpty, "A query alone cannot identify a place")
    interactor.handle(.didSelectResult(result, withQuery: query))
    let location = try XCTUnwrap(MikshatSearchHistoryStore().locations.first)
    XCTAssertEqual(location.title, result.titleText)
    XCTAssertEqual(location.subtitle, result.addressText)
    XCTAssertEqual(location.query, query.text)
    XCTAssertEqual(location.latitude, result.coordinate.latitude)
    XCTAssertEqual(location.longitude, result.coordinate.longitude)
    interactor.handle(.didSelect(SearchQuery(historyLocation: location)))
    XCTAssertEqual(searchManager.searchQueryCallCount, 1)
    XCTAssertEqual(openedHistoryCoordinate?.latitude, result.coordinate.latitude)
    XCTAssertEqual(openedHistoryCoordinate?.longitude, result.coordinate.longitude)
    XCTAssertEqual(openedHistoryTitle, result.titleText)
  }

  func test_GivenSavedHistoryPointInRoutePicker_WhenSelected_ThenSelectsThatPointWithoutMapSearch() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)
    let location = MikshatSearchLocation(id: "route", title: "Destination", subtitle: "Stored address", query: "query",
                                         latitude: 25, longitude: 47)
    interactor.handle(.didSelect(SearchQuery(historyLocation: location)))
    XCTAssertEqual(routePointSelector.selectedHistoryLocation, location)
    XCTAssertNil(routePointSelector.selectedSearchResult)
    XCTAssertNil(openedHistoryCoordinate)
    XCTAssertEqual(searchManager.searchQueryCallCount, 0)
    XCTAssertEqual(searchManager.showResultCallCount, 0)
    XCTAssertEqual(currentState, .closed)
  }

  func test_GivenInitialState_WhenSelectCategory_ThenUpdateSearchResultsAndShowMap() {
    interactor.handle(.openSearch)

    let query = SearchQuery("category", source: .category)
    interactor.handle(.didSelect(query))

    XCTAssertEqual(view.viewModel.presentationStep, .halfScreen)
    XCTAssertEqual(view.viewModel.contentState, .searching)
    XCTAssertEqual(view.viewModel.searchingText, query.text)
    XCTAssertEqual(view.viewModel.isTyping, false)

    let results = SearchResult.stubResults()
    searchManager.results = results

    XCTAssertEqual(currentState, .searching)
    XCTAssertEqual(view.viewModel.presentationStep, .halfScreen)
    XCTAssertEqual(view.viewModel.contentState, .results(results))
    XCTAssertEqual(view.viewModel.searchingText, nil)
    XCTAssertEqual(view.viewModel.isTyping, false)
  }

  func test_GivenInitialState_WhenTypeText_ThenUpdateSearchResults() {
    interactor.handle(.openSearch)

    let query = SearchQuery("text", source: .typedText)
    interactor.handle(.didType(query))

    XCTAssertEqual(view.viewModel.presentationStep, .expanded)
    XCTAssertEqual(view.viewModel.contentState, .searching)
    XCTAssertEqual(view.viewModel.searchingText, nil)
    XCTAssertEqual(view.viewModel.isTyping, true)

    let results = SearchResult.stubResults()
    searchManager.results = results

    XCTAssertEqual(currentState, .searching)
    XCTAssertEqual(view.viewModel.presentationStep, .expanded)
    XCTAssertEqual(view.viewModel.contentState, .results(results))
    XCTAssertEqual(view.viewModel.searchingText, nil)
    XCTAssertEqual(view.viewModel.isTyping, true)
  }

  func test_GivenInitialState_WhenTypeDebugCommand_ThenShowNoResults() {
    interactor.handle(.openSearch)

    interactor.handle(.didType(SearchQuery("?dark", source: .typedText)))

    XCTAssertEqual(view.viewModel.presentationStep, .expanded)
    XCTAssertEqual(view.viewModel.contentState, .noResults)
    XCTAssertEqual(view.viewModel.isTyping, true)
  }

  func test_GivenInitialState_WhenSelectDebugCommandFromHistory_ThenShowNoResults() {
    interactor.handle(.openSearch)

    interactor.handle(.didSelect(SearchQuery("?dark", source: .history)))

    XCTAssertEqual(view.viewModel.presentationStep, .halfScreen)
    XCTAssertEqual(view.viewModel.contentState, .noResults)
    XCTAssertEqual(view.viewModel.isTyping, false)
  }

  func test_GivenInitialState_WhenTapSearch_ThenUpdateSearchResultsAndShowMap() {
    interactor.handle(.openSearch)

    let query = SearchQuery("text", source: .typedText)
    interactor.handle(.didType(query))

    let results = SearchResult.stubResults()
    searchManager.results = results

    XCTAssertEqual(view.viewModel.presentationStep, .expanded)
    XCTAssertEqual(view.viewModel.contentState, .results(results))
    XCTAssertEqual(view.viewModel.searchingText, nil)
    XCTAssertEqual(view.viewModel.isTyping, true)

    interactor.handle(.searchButtonDidTap(query))

    XCTAssertEqual(currentState, .searching)
    XCTAssertEqual(view.viewModel.presentationStep, .compact)
    XCTAssertEqual(view.viewModel.contentState, .results(results))
    XCTAssertEqual(view.viewModel.searchingText, nil)
    XCTAssertEqual(view.viewModel.isTyping, false)
  }

  func test_GivenHalfScreenSearch_WhenTapSearch_ThenShowMapInCompact() {
    interactor.handle(.openSearch)
    interactor.handle(.didUpdatePresentationStep(.halfScreen))
    XCTAssertEqual(view.viewModel.presentationStep, .halfScreen)

    let query = SearchQuery("text", source: .typedText)
    interactor.handle(.searchButtonDidTap(query))
    interactor.handle(.didUpdatePresentationStep(view.viewModel.presentationStep))

    XCTAssertEqual(view.viewModel.presentationStep, .compact)
    XCTAssertEqual(view.viewModel.isTyping, false)
    XCTAssertEqual(searchManager.searchMode(), .everywhereAndViewport)
  }

  func test_GivenResults_WhenTapSearch_ThenUpdateViewport() {
    interactor.handle(.openSearch)
    let query = SearchQuery("text", source: .typedText)
    interactor.handle(.didType(query))
    searchManager.results = SearchResult.stubResults()

    interactor.handle(.searchButtonDidTap(query))
    XCTAssertEqual(searchManager.updateViewportCallsCount, 1)
  }

  func test_GivenRouting_WhenTapSearch_ThenHideSearchAndKeepViewport() {
    presenter = SearchOnMapPresenter(shouldHideForRouting: true,
                                     didChangeState: { [weak self] in self?.currentState = $0 })
    interactor = SearchOnMapInteractor(presenter: presenter, searchManager: searchManager)
    presenter.view = view
    interactor.handle(.openSearch)

    let query = SearchQuery("text", source: .typedText)
    interactor.handle(.didType(query))
    interactor.handle(.searchButtonDidTap(query))

    XCTAssertEqual(view.viewModel.presentationStep, .hidden)
    XCTAssertEqual(searchManager.updateViewportCallsCount, 0)
  }

  func test_GivenSearchIsOpened_WhenMapIsDragged_ThenCollapseSearchScreen() {
    interactor.handle(.openSearch)
    XCTAssertEqual(view.viewModel.presentationStep, .expanded)

    interactor.handle(.didStartDraggingMap)
    XCTAssertEqual(view.viewModel.presentationStep, .compact)
  }

  func test_GivenSearchIsOpened_WhenModalPresentationScreenIsDragged_ThenDisableTyping() {
    interactor.handle(.openSearch)
    XCTAssertEqual(view.viewModel.isTyping, true)

    interactor.handle(.didStartDraggingSearch)
    XCTAssertEqual(view.viewModel.isTyping, false)
  }

  func test_GivenResultsOnScreen_WhenSelectResult_ThenHideSearch() {
    interactor.handle(.openSearch)
    XCTAssertEqual(view.viewModel.isTyping, true)

    let query = SearchQuery("text", source: .typedText)
    interactor.handle(.didSelect(query))

    let results = SearchResult.stubResults()
    searchManager.results = results

    interactor.handle(.didSelectResult(results[0], withQuery: query))
    if isiPad {
      XCTAssertEqual(currentState, .searching)
      XCTAssertEqual(view.viewModel.presentationStep, .expanded)
    } else {
      XCTAssertEqual(currentState, .hidden)
      XCTAssertEqual(view.viewModel.presentationStep, .hidden)
    }
  }

  func test_GivenSearchIsActive_WhenSelectPlaceOnMap_ThenHideSearch() {
    interactor.handle(.openSearch)
    XCTAssertEqual(view.viewModel.presentationStep, .expanded)

    interactor.handle(.didSelectPlaceOnMap)

    if isiPad {
      XCTAssertNotEqual(view.viewModel.presentationStep, .hidden)
    } else {
      XCTAssertEqual(view.viewModel.presentationStep, .hidden)
    }
  }

  func test_GivenSearchIsHidden_WhenPPDeselected_ThenShowSearch() {
    interactor.handle(.openSearch)
    XCTAssertEqual(view.viewModel.isTyping, true)

    let query = SearchQuery("text", source: .typedText)
    interactor.handle(.didSelect(query))

    let results = SearchResult.stubResults()
    searchManager.results = results

    interactor.handle(.didSelectResult(results[0], withQuery: query))
    if isiPad {
      XCTAssertEqual(currentState, .searching)
      XCTAssertEqual(view.viewModel.presentationStep, .expanded)
    } else {
      XCTAssertEqual(currentState, .hidden)
      XCTAssertEqual(view.viewModel.presentationStep, .hidden)
    }

    interactor.handle(.didDeselectPlaceOnMap)
    XCTAssertEqual(currentState, .searching)
    XCTAssertEqual(view.viewModel.presentationStep, .expanded)
  }

  func test_GivenSearchIsOpen_WhenCloseSearch_ThenHideSearch() {
    interactor.handle(.openSearch)
    XCTAssertEqual(view.viewModel.presentationStep, .expanded)

    interactor.handle(.closeSearch)
    XCTAssertEqual(currentState, .closed)
  }

  func test_GivenSearchIsBeingReplaced_WhenClosed_ThenDoesNotNotifyObservers() {
    interactor.handle(.openSearch)

    interactor.closeForReplacement()

    XCTAssertEqual(view.closeCallCount, 1)
    XCTAssertEqual(currentState, .searching)
  }

  func test_GivenSearchHasText_WhenClearSearch_ThenShowHistoryAndCategory() {
    interactor.handle(.openSearch)

    let query = SearchQuery("text", source: .typedText)
    interactor.handle(.didSelect(query))

    interactor.handle(.clearButtonDidTap)
    XCTAssertEqual(view.viewModel.presentationStep, .expanded)
    XCTAssertEqual(view.viewModel.contentState, .historyAndCategory)
    XCTAssertEqual(view.viewModel.searchingText, "")
    XCTAssertEqual(view.viewModel.isTyping, true)
  }

  func test_GivenSearchExecuted_WhenNoResults_ThenShowNoResults() {
    interactor.handle(.openSearch)

    let query = SearchQuery("text", source: .typedText)
    interactor.handle(.didSelect(query))

    searchManager.results = SearchOnMap.SearchResults([])
    interactor.onSearchCompleted()

    XCTAssertEqual(view.viewModel.contentState, .noResults)
  }

  func test_GivenSearchIsActive_WhenSelectSuggestion_ThenReplaceWithSuggestion() {
    interactor.handle(.openSearch)

    let query = SearchQuery("ca", source: .typedText)
    interactor.handle(.didType(query))

    let result = SearchResult(titleText: "", type: .suggestion, suggestion: "cafe")
    interactor.handle(.didSelectResult(result, withQuery: query))

    XCTAssertEqual(view.viewModel.searchingText, "cafe")
    XCTAssertEqual(view.viewModel.presentationStep, .expanded)
    XCTAssertEqual(view.viewModel.contentState, .searching)
    XCTAssertEqual(view.viewModel.isTyping, true)
  }

  func test_GivenSearchIsActive_WhenPasteDeeplink_ThenShowResult() {
    interactor.handle(.openSearch)

    let query = SearchQuery("om://search?cll=42.0,44.0&query=Toilet", source: .deeplink)
    interactor.handle(.didSelect(query))

    let result = SearchResult(titleText: "some result", type: .regular, suggestion: "")
    let results = SearchOnMap.SearchResults([result])
    searchManager.results = results
    interactor.onSearchCompleted()

    XCTAssertEqual(view.viewModel.contentState, .results(results))
    XCTAssertEqual(view.viewModel.presentationStep, .halfScreen)
    XCTAssertEqual(view.viewModel.isTyping, false) // No typing when deeplink is used
  }

  func test_GivenSearchIsActive_WhenPresentationStepUpdate_ThenUpdateSearchMode() {
    interactor.handle(.openSearch)
    interactor.handle(.didUpdatePresentationStep(view.viewModel.presentationStep))
    XCTAssertEqual(searchManager.searchMode(), isiPad ? .everywhereAndViewport : .everywhere)

    interactor.handle(.didUpdatePresentationStep(.halfScreen))
    XCTAssertEqual(searchManager.searchMode(), .everywhereAndViewport)

    interactor.handle(.didUpdatePresentationStep(.compact))
    XCTAssertEqual(searchManager.searchMode(), .everywhereAndViewport)

    interactor.handle(.didUpdatePresentationStep(.hidden))
    XCTAssertEqual(searchManager.searchMode(), .viewport)

    interactor.handle(.didUpdatePresentationStep(.expanded))
    XCTAssertEqual(searchManager.searchMode(), isiPad ? .everywhereAndViewport : .everywhere)
  }

  func test_GivenRoutePointSearch_WhenSearchOpens_ThenShowsRoutePointActions() {
    configureRoutePointSearch()

    interactor.handle(.openSearch)

    XCTAssertEqual(view.viewModel.routePointActions,
                   .init(title: routePointSelector.title, canSelectCurrentLocation: true))
  }

  func test_GivenRoutePointSearch_WhenRegularResultIsSelected_ThenSelectsRoutePointAndCloses() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)
    let result = SearchLocationResultStub()

    interactor.handle(.didSelectResult(result, withQuery: SearchQuery("cafe", source: .typedText)))

    XCTAssertTrue(routePointSelector.selectedSearchResult === result)
    XCTAssertEqual(searchManager.showResultCallCount, 0)
    XCTAssertEqual(view.closeCallCount, 1)
    XCTAssertEqual(currentState, .closed)
    assertRoutePointSearchClosed()
  }

  func test_GivenRoutePointSearch_WhenCategoryIsSelected_ThenShowsSelectableResults() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)
    let query = SearchQuery("cafe", source: .category)

    interactor.handle(.didSelect(query))

    XCTAssertEqual(view.viewModel.presentationStep, .halfScreen)
    let results = SearchResult.stubResults()
    searchManager.results = results
    XCTAssertEqual(view.viewModel.contentState, .results(results))

    interactor.handle(.didSelectResult(results[0], withQuery: query))

    XCTAssertTrue(routePointSelector.selectedSearchResult === results[0])
    XCTAssertEqual(view.closeCallCount, 1)
  }

  func test_GivenRoutePointSearch_WhenResultsAreShown_ThenRetainsRoutePointActionsConfiguration() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)
    let query = SearchQuery("cafe", source: .typedText)

    interactor.handle(.didSelect(query))
    searchManager.results = SearchResult.stubResults()

    XCTAssertNotNil(view.viewModel.routePointActions)
  }

  func test_GivenRoutePointSearch_WhenCurrentLocationIsSelected_ThenSelectsAndCloses() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)

    interactor.handle(.currentLocationButtonDidTap)

    XCTAssertEqual(routePointSelector.selectCurrentLocationCallCount, 1)
    XCTAssertEqual(view.closeCallCount, 1)
    assertRoutePointSearchClosed()
  }

  func test_GivenRoutePointSearch_WhenChoosingOnMap_ThenPresentsPickerAndCommitsPoint() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)

    interactor.handle(.chooseOnMapButtonDidTap)

    XCTAssertEqual(view.mapPointPickerTitle, routePointSelector.title)
    XCTAssertEqual(view.viewModel.presentationStep, .hidden)
    XCTAssertFalse(view.viewModel.isTyping)
    XCTAssertEqual(currentState, .mapPointPicker)

    let point = CGPoint(x: 12, y: 34)
    interactor.handle(.didSelectMapPoint(point))

    XCTAssertEqual(routePointSelector.selectedMapPoint, point)
    XCTAssertEqual(view.closeCallCount, 1)
    assertRoutePointSearchClosed()
  }

  func test_GivenHiddenRoutePointSearch_WhenLocationAvailabilityChanges_ThenReopensWithCurrentActions() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)

    for canSelectCurrentLocation in [false, true] {
      interactor.handle(.hideSearch)
      let renderCount = view.renderCallCount
      routePointSelector.canSelectCurrentLocation = canSelectCurrentLocation

      interactor.processMyPositionStateModeEvent(.notFollowNoPosition)

      XCTAssertEqual(currentState, .hidden)
      XCTAssertEqual(view.renderCallCount, renderCount)
      interactor.handle(.didDeselectPlaceOnMap)
      XCTAssertEqual(view.viewModel.routePointActions?.canSelectCurrentLocation, canSelectCurrentLocation)
      XCTAssertEqual(currentState, .searching)
    }
  }

  func test_GivenMapPointPicker_WhenLocationAvailabilityChanges_ThenKeepsPickerUntilSelectionFinishes() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)
    interactor.handle(.chooseOnMapButtonDidTap)
    let renderCount = view.renderCallCount
    routePointSelector.canSelectCurrentLocation = false

    interactor.processMyPositionStateModeEvent(.notFollowNoPosition)

    XCTAssertEqual(currentState, .mapPointPicker)
    XCTAssertEqual(view.viewModel.presentationStep, .hidden)
    XCTAssertEqual(view.renderCallCount, renderCount)

    routePointSelector.shouldSelect = false
    interactor.handle(.didSelectMapPoint(CGPoint(x: 12, y: 34)))

    XCTAssertEqual(currentState, .searching)
    XCTAssertEqual(view.viewModel.routePointActions?.canSelectCurrentLocation, false)
    XCTAssertTrue(routePointSelector.isActive)
  }

  func test_GivenRoutePointSearch_WhenSearchIsSubmitted_ThenShowsResultsOnMapAndKeepsSelectionActive() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)
    let query = SearchQuery("cafe", source: .typedText)
    interactor.handle(.didType(query))
    searchManager.results = SearchResult.stubResults()

    interactor.handle(.searchButtonDidTap(query))

    XCTAssertEqual(view.viewModel.presentationStep, .compact)
    XCTAssertEqual(searchManager.updateViewportCallsCount, 1)
    XCTAssertTrue(routePointSelector.isActive)
    XCTAssertEqual(view.closeCallCount, 0)
  }

  func test_GivenRoutePointSearch_WhenReplaced_ThenCancelsSelectionWithoutNotifyingClosure() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)

    interactor.closeForReplacement()

    XCTAssertFalse(routePointSelector.isActive)
    XCTAssertEqual(routePointSelector.cancelCallCount, 1)
    XCTAssertEqual(view.closeCallCount, 1)
    XCTAssertEqual(currentState, .searching)
  }

  func test_GivenMapPointPicker_WhenCancelled_ThenCancelsRoutePointSearch() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)
    interactor.handle(.chooseOnMapButtonDidTap)

    interactor.handle(.didCancelMapPoint)

    XCTAssertEqual(routePointSelector.cancelCallCount, 1)
    XCTAssertEqual(view.closeCallCount, 1)
    XCTAssertEqual(currentState, .closed)
  }

  func test_GivenRoutePointSearch_WhenResultIsRejected_ThenKeepsSearchOpen() {
    configureRoutePointSearch()
    routePointSelector.shouldSelect = false
    interactor.handle(.openSearch)
    let query = SearchQuery("cafe", source: .typedText)
    interactor.handle(.didSelect(query))
    let results = SearchResult.stubResults()
    searchManager.results = results

    interactor.handle(.didSelectResult(results[0], withQuery: query))

    XCTAssertTrue(routePointSelector.selectedSearchResult === results[0])
    XCTAssertEqual(view.closeCallCount, 0)
    XCTAssertEqual(searchManager.showResultCallCount, 0)
  }

  func test_GivenRoutePointSearch_WhenCurrentLocationIsRejected_ThenKeepsSearchOpen() {
    configureRoutePointSearch()
    routePointSelector.shouldSelect = false
    interactor.handle(.openSearch)

    interactor.handle(.currentLocationButtonDidTap)

    XCTAssertEqual(routePointSelector.selectCurrentLocationCallCount, 1)
    XCTAssertEqual(view.closeCallCount, 0)
  }

  func test_GivenMapPointPicker_WhenPointIsRejected_ThenReopensSearch() {
    configureRoutePointSearch()
    routePointSelector.shouldSelect = false
    interactor.handle(.openSearch)
    interactor.handle(.chooseOnMapButtonDidTap)
    XCTAssertEqual(view.viewModel.presentationStep, .hidden)

    let point = CGPoint(x: 12, y: 34)
    interactor.handle(.didSelectMapPoint(point))

    XCTAssertEqual(routePointSelector.selectedMapPoint, point)
    XCTAssertEqual(view.closeCallCount, 0)
    XCTAssertNotEqual(view.viewModel.presentationStep, .hidden)
  }

  func test_GivenRoutePointSearch_WhenClosed_ThenCancelsPendingSelection() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)

    interactor.handle(.closeSearch)

    XCTAssertEqual(routePointSelector.cancelCallCount, 1)
  }

  func test_GivenClosedRoutePointSearch_WhenLateSearchCallbacksArrive_ThenIgnoresResults() {
    configureRoutePointSearch()
    interactor.handle(.openSearch)
    interactor.handle(.currentLocationButtonDidTap)
    let renderCount = view.renderCallCount

    // Assigning results emits onSearchCompleted through SearchManagerMock.
    searchManager.results = SearchResult.stubResults()
    XCTAssertEqual(view.renderCallCount, renderCount)
    XCTAssertEqual(currentState, .closed)

    interactor.onSearchResultsUpdated()
    XCTAssertEqual(view.renderCallCount, renderCount)
    XCTAssertEqual(currentState, .closed)
  }

  private func configureRoutePointSearch() {
    routePointSelector = RoutePointSelectorMock()
    presenter = SearchOnMapPresenter(shouldHideForRouting: false,
                                     routePointActions: .init(title: routePointSelector.title,
                                                              canSelectCurrentLocation: true),
                                     didChangeState: { [weak self] in self?.currentState = $0 })
    interactor = SearchOnMapInteractor(presenter: presenter,
                                       searchManager: searchManager,
                                       routePointSelector: routePointSelector)
    view = SearchOnMapViewMock()
    presenter.view = view
  }

  private func assertRoutePointSearchClosed(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(routePointSelector.isActive, file: file, line: line)
    XCTAssertEqual(searchManager.clearCallCount, 1, file: file, line: line)
    XCTAssertEqual(currentState, .closed, file: file, line: line)
  }
}

// MARK: - Mocks

private class SearchOnMapViewMock: SearchOnMapView {
  var viewModel: SearchOnMap.ViewModel = .initial
  var scrollViewDelegate: (any UIScrollViewDelegate)?
  var closeCallCount = 0
  var renderCallCount = 0
  var mapPointPickerTitle: String?

  func render(_ viewModel: SearchOnMap.ViewModel) {
    renderCallCount += 1
    self.viewModel = viewModel
  }

  func close() {
    closeCallCount += 1
  }

  func show() {}

  func showMapPointPicker(title: String) {
    mapPointPickerTitle = title
  }
}

private class SearchManagerMock: SearchManager {
  static var observers = ListenerContainer<MWMSearchObserver>()
  static var results = SearchOnMap.SearchResults.empty {
    didSet {
      observers.forEach { $0.onSearchCompleted?() }
    }
  }

  private static var _searchMode: SearchMode = .everywhere
  static var updateViewportCallsCount = 0
  static var showResultCallCount = 0
  static var clearCallCount = 0
  static var searchQueryCallCount = 0
  static var savedQueries: [SearchQuery] = []

  static func add(_ observer: any MWMSearchObserver) {
    observers.addListener(observer)
  }

  static func remove(_ observer: any MWMSearchObserver) {
    observers.removeListener(observer)
  }

  static func save(_ query: SearchQuery) { savedQueries.append(query) }
  // Debug commands start no search.
  static func searchQuery(_ query: SearchQuery) -> Bool {
    searchQueryCallCount += 1
    return !query.text.hasPrefix("?")
  }
  static func showResult(at _: UInt) {
    showResultCallCount += 1
  }

  static func updateViewportWithResults() { updateViewportCallsCount += 1 }
  static func clear() { clearCallCount += 1 }
  static func getResults() -> [SearchResult] { results.results }
  static func searchMode() -> SearchMode { _searchMode }
  static func setSearchMode(_ mode: SearchMode) { _searchMode = mode }
}

private final class RoutePointSelectorMock: RoutePointSelecting {
  var isActive = true
  var title = "Choose destination"
  var canSelectCurrentLocation = true
  var shouldSelect = true
  var selectCurrentLocationCallCount = 0
  var selectedSearchResult: SearchResult?
  var selectedMapPoint: CGPoint?
  var selectedHistoryLocation: MikshatSearchLocation?
  var cancelCallCount = 0

  func selectCurrentLocation() -> Bool {
    selectCurrentLocationCallCount += 1
    return completeSelection()
  }

  func select(searchResult: SearchResult) -> Bool {
    selectedSearchResult = searchResult
    return completeSelection()
  }

  func select(mapPoint: CGPoint) -> Bool {
    selectedMapPoint = mapPoint
    return completeSelection()
  }

  func select(historyLocation: MikshatSearchLocation) -> Bool {
    selectedHistoryLocation = historyLocation
    return completeSelection()
  }

  func cancel() {
    cancelCallCount += 1
    isActive = false
  }

  private func completeSelection() -> Bool {
    if shouldSelect {
      isActive = false
    }
    return shouldSelect
  }
}

private extension SearchResult {
  static func stubResults() -> SearchOnMap.SearchResults {
    SearchOnMap.SearchResults([
      SearchLocationResultStub(),
      SearchLocationResultStub(),
      SearchLocationResultStub(),
    ])
  }
}

private final class SearchLocationResultStub: SearchResult {
  override var titleText: String { "Selected place" }
  override var addressText: String { "Actual region" }
  override var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 24.7136, longitude: 46.6753) }
  override var highlightRanges: [NSValue] { [] }
}
