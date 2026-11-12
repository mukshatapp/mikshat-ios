@testable import Organic_Maps__Debug_
import XCTest
import UIKit
import CoreLocation

final class SearchHistoryOnlyTests: XCTestCase {
  private let selectedIndexKey = "SearchTabViewController_selectedIndexKey"
  private var defaults: UserDefaults!
  private var defaultsSuite: String!
  private var previousHistoryEnabled = true
  private var previousLocations: Any?

  override func setUpWithError() throws {
    try super.setUpWithError()
    defaultsSuite = "SearchHistoryOnlyTests.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
    previousHistoryEnabled = Settings.searchHistoryEnabled()
    previousLocations = UserDefaults.standard.object(forKey: "mikshat_search_locations")
    Settings.setSearchHistoryEnabled(true)
    HistoryOnlyFrameworkStub.queries = []
    HistoryOnlyFrameworkStub.categoryRequests = 0
    HistoryOnlyFrameworkStub.clearRequests = 0
  }

  override func tearDown() {
    Settings.setSearchHistoryEnabled(previousHistoryEnabled)
    if let previousLocations {
      UserDefaults.standard.set(previousLocations, forKey: "mikshat_search_locations")
    } else {
      UserDefaults.standard.removeObject(forKey: "mikshat_search_locations")
    }
    defaults.removePersistentDomain(forName: defaultsSuite)
    defaults = nil
    super.tearDown()
  }

  func test_LegacyCategoryAndInvalidIndicesOpenDirectHistoryWithoutPager() throws {
    for oldIndex in [-99, 0, 1, 99] {
      defaults.set(oldIndex, forKey: selectedIndexKey)
      let controller = makeController()
      let history = try historyController(in: controller)
      let table = try historyTable(in: history)
      XCTAssertEqual(defaults.integer(forKey: selectedIndexKey), 0)
      XCTAssertEqual(controller.children.count, 1)
      XCTAssertTrue(descendants(of: UICollectionView.self, in: controller.view).isEmpty)
      XCTAssertEqual(HistoryOnlyFrameworkStub.categoryRequests, 0)

      // The first history row begins directly below the existing search header;
      // there is no retained 46-point tab bar or horizontal page to consume space.
      for size in [CGSize(width: 320, height: 480), CGSize(width: 480, height: 220)] {
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        XCTAssertEqual(history.view.frame, controller.view.bounds)
        XCTAssertEqual(table.frame, history.view.bounds)
        XCTAssertFalse(table.isPagingEnabled)
      }
    }
  }

  func test_HistorySelectionAndCoordinateDirectionTargetRemainIntact() throws {
    let coordinate = CLLocationCoordinate2D(latitude: 24.7136, longitude: 46.6753)
    let savedQuery = "Saved map point"
    HistoryOnlyFrameworkStub.queries = [savedQuery, "Text query"]
    MikshatSearchLocations.remember(coordinate, query: savedQuery)
    let controller = makeController()
    let delegate = HistoryOnlyDelegateSpy()
    controller.delegate = delegate
    let history = try historyController(in: controller)
    let table = try historyTable(in: history)
    XCTAssertEqual(table.numberOfRows(inSection: 0), 3)
    let row = try XCTUnwrap(table.dataSource?.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0)))
    XCTAssertEqual(row.textLabel?.text, savedQuery)
    let arrow = try XCTUnwrap(row.accessoryView as? MikshatDirectionIndicator)
    let target = try XCTUnwrap(arrow.target)
    XCTAssertEqual(target.latitude, coordinate.latitude)
    XCTAssertEqual(target.longitude, coordinate.longitude)

    history.tableView(table, didSelectRowAt: IndexPath(row: 0, section: 0))
    XCTAssertEqual(delegate.query?.text, savedQuery + " ")
    XCTAssertEqual(delegate.query?.source, .history)
  }

  func test_RotatedHistoryAccessoryKeepsFixedGeometryThroughTableLayoutAndReuse() throws {
    let query = "24.7136, 46.6753"
    HistoryOnlyFrameworkStub.queries = [query, "Text query"]
    let controller = makeController()
    let history = try historyController(in: controller)
    let table = try historyTable(in: history)
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first {
      $0.activationState == .foregroundActive
    }
    let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = controller
    window.isHidden = false
    defer { window.isHidden = true }
    window.layoutIfNeeded()
    table.layoutIfNeeded()
    let row = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 0, section: 0)) as? SearchHistoryCell)
    let arrow = try XCTUnwrap(row.accessoryView as? MikshatDirectionIndicator)
    let image = try XCTUnwrap(arrow.subviews.compactMap { $0 as? UIImageView }.first)
    XCTAssertNotNil(arrow.window, "Exercise UIKit's attached table accessory layout")

    for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
      table.semanticContentAttribute = direction
      row.semanticContentAttribute = direction
      for width in [CGFloat(320), 390, 844] {
        window.frame.size.width = width
        window.layoutIfNeeded()
        for bearing in [Double(45), 135, 225, 315] {
          arrow.renderDirection(bearing: bearing, heading: 0)
          for _ in 0..<12 {
            table.setNeedsLayout()
            row.setNeedsLayout()
            table.layoutIfNeeded()
            row.layoutIfNeeded()
            arrow.layoutIfNeeded()
            XCTAssertEqual(arrow.transform, .identity)
            XCTAssertEqual(arrow.frame.size, CGSize(width: 28, height: 28))
            XCTAssertEqual(arrow.bounds.size, CGSize(width: 28, height: 28))
            XCTAssertEqual(image.bounds.size, CGSize(width: 28, height: 28))
            XCTAssertEqual(image.center, CGPoint(x: 14, y: 14))
            XCTAssertEqual(image.transform.a, CGFloat(cos(bearing * .pi / 180)), accuracy: 0.0001)
            XCTAssertEqual(image.transform.b, CGFloat(sin(bearing * .pi / 180)), accuracy: 0.0001)
            XCTAssertLessThanOrEqual(image.frame.width, 40)
            XCTAssertLessThanOrEqual(image.frame.height, 40)
            for value in [arrow.frame.minX, arrow.frame.minY, image.frame.minX, image.frame.minY,
                          image.frame.width, image.frame.height] {
              XCTAssertTrue(value.isFinite)
            }
          }
          XCTAssertEqual(arrow.alpha, 1)
          XCTAssertFalse(arrow.accessibilityElementsHidden)
          XCTAssertEqual(arrow.accessibilityValue, String(format: "%.0f°", bearing))
        }
      }
    }

    // Reset a genuinely rotated accessory before it is configured for another
    // row; both clear and text-only rows must drop its target and VoiceOver value.
    row.prepareForReuse()
    XCTAssertNil(row.accessoryView)
    XCTAssertNil(arrow.target)
    XCTAssertEqual(image.transform, .identity)
    XCTAssertEqual(arrow.alpha, 0)
    XCTAssertTrue(arrow.accessibilityElementsHidden)
    XCTAssertNil(arrow.accessibilityValue)
    for content in [SearchHistoryCell.Content.clear, .query("Text query")] {
      row.configure(for: content)
      XCTAssertNil(row.accessoryView)
      XCTAssertNil(arrow.target)
    }
    row.configure(for: .query("25, 47"))
    XCTAssertTrue(row.accessoryView === arrow)
    XCTAssertEqual(try XCTUnwrap(arrow.target).latitude, 25)
    XCTAssertEqual(try XCTUnwrap(arrow.target).longitude, 47)
    arrow.renderDirection(bearing: 135, heading: 0)
    row.setNeedsLayout()
    row.layoutIfNeeded()
    XCTAssertEqual(arrow.transform, .identity)
    XCTAssertEqual(arrow.frame.size, CGSize(width: 28, height: 28))
    XCTAssertEqual(image.bounds.size, CGSize(width: 28, height: 28))
    XCTAssertEqual(arrow.alpha, 1)
    XCTAssertFalse(arrow.accessibilityElementsHidden)
  }

  func test_EmptyAndDisabledHistoryStayEmptyWithoutFallingBackToCategories() throws {
    let controller = makeController()
    let history = try historyController(in: controller)
    let table = try historyTable(in: history)
    let placeholder = try XCTUnwrap(history.view.subviews.compactMap { $0 as? PlaceholderView }.first)
    XCTAssertEqual(table.numberOfRows(inSection: 0), 0)
    XCTAssertFalse(placeholder.isHidden)

    HistoryOnlyFrameworkStub.queries = ["Existing private query"]
    Settings.setSearchHistoryEnabled(false)
    controller.reloadSearchHistory()
    XCTAssertEqual(table.numberOfRows(inSection: 0), 0)
    XCTAssertFalse(placeholder.isHidden)
    XCTAssertEqual(HistoryOnlyFrameworkStub.categoryRequests, 0)

    Settings.setSearchHistoryEnabled(true)
    controller.reloadSearchHistory()
    XCTAssertEqual(table.numberOfRows(inSection: 0), 2)
    XCTAssertTrue(placeholder.isHidden)
  }

  func test_ClearHistoryStillClearsQueriesAndSavedDirectionTargets() throws {
    let query = "Point to clear"
    HistoryOnlyFrameworkStub.queries = [query]
    MikshatSearchLocations.remember(CLLocationCoordinate2D(latitude: 25, longitude: 47), query: query)
    let controller = makeController()
    let history = try historyController(in: controller)
    let table = try historyTable(in: history)
    history.tableView(table, didSelectRowAt: IndexPath(row: 1, section: 0))
    XCTAssertEqual(HistoryOnlyFrameworkStub.clearRequests, 1)
    XCTAssertEqual(table.numberOfRows(inSection: 0), 0)
    XCTAssertNil(MikshatSearchLocations.coordinate(for: query))
  }

  func test_PresentationInsetAndVerticalScrollingReachTheSearchSheet() throws {
    let controller = makeController()
    let delegate = HistoryOnlyDelegateSpy()
    controller.delegate = delegate
    let history = try historyController(in: controller)
    let table = try historyTable(in: history)
    controller.presentationFrameDidChange(CGRect(x: 0, y: 120, width: 320, height: 500))
    XCTAssertEqual(table.contentInset.bottom, 120)
    history.scrollViewDidScroll(table)
    XCTAssertTrue(delegate.scrolledView === table)
    var offset = CGPoint(x: 0, y: 80)
    history.scrollViewWillEndDragging(table, withVelocity: CGPoint(x: 0, y: 2), targetContentOffset: &offset)
    XCTAssertEqual(offset, .zero)
  }

  func test_PlaceInformationEndsAtWeatherActionAfterUnchangedCoordinates() throws {
    let data = WeatherEntryInfoStub()
    let controller = UIStoryboard.instance(.placePage).instantiateViewController(ofType: PlacePageInfoViewController.self)
    controller.placePageInfoData = data
    var weatherTaps = 0
    controller.didTapWeather = { weatherTaps += 1 }
    controller.loadViewIfNeeded()
    let fitting = controller.view.systemLayoutSizeFitting(CGSize(width: 320, height: 0),
                                                         withHorizontalFittingPriority: .required,
                                                         verticalFittingPriority: .fittingSizeLevel)
    controller.view.frame = CGRect(origin: .zero, size: fitting)
    controller.view.layoutIfNeeded()
    let coordinates = controller.stackView.arrangedSubviews.compactMap { $0 as? MikshatCoordinateRow }
    XCTAssertEqual(coordinates.count, 2)
    let weather = try XCTUnwrap(controller.stackView.arrangedSubviews.last as? InfoItemView)
    XCTAssertEqual(weather.accessibilityIdentifier, "placePage.weather")
    XCTAssertGreaterThanOrEqual(weather.frame.minY, try XCTUnwrap(coordinates.last).frame.maxY)
    XCTAssertEqual(weather.frame.maxY, controller.view.bounds.maxY, accuracy: 1)
    XCTAssertGreaterThan(fitting.height, 176)
    XCTAssertLessThan(fitting.height, 400)
    weather.infoLabelTapHandler?()
    weather.iconButton.sendActions(for: .touchUpInside)
    weather.accessoryButton.sendActions(for: .touchUpInside)
    XCTAssertEqual(weatherTaps, 3)
  }

  func test_ShortPlacePageDragStopsAtItsContentEnd() throws {
    let storyboard = UIStoryboard.instance(.placePage)
    let controller = try XCTUnwrap(storyboard.instantiateInitialViewController() as? PlacePageViewController)
    controller.layout = ShortPlacePageLayout(storyboard: storyboard)
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    controller.view.layoutIfNeeded()
    controller.updatePreviewOffset()
    let scrollView = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? PlacePageScrollView }.first)
    let maximumOffset = scrollView.contentSize.height - scrollView.bounds.height
    XCTAssertLessThan(maximumOffset, 0, "Short content must not be stretched to the viewport height")
    scrollView.contentOffset = CGPoint(x: 0, y: maximumOffset)
    for velocity in [CGFloat(0), CGFloat(1)] {
      var target = CGPoint.zero
      controller.scrollViewWillEndDragging(scrollView,
                                           withVelocity: CGPoint(x: 0, y: velocity),
                                           targetContentOffset: &target)
      XCTAssertEqual(target.y, maximumOffset, accuracy: 1)
    }
  }

  private func makeController() -> SearchTabViewController {
    let controller = SearchTabViewController(frameworkHelper: HistoryOnlyFrameworkStub.self, userDefaults: defaults)
    controller.loadViewIfNeeded()
    return controller
  }

  private func historyController(in controller: SearchTabViewController) throws -> SearchHistoryViewController {
    try XCTUnwrap(controller.children.compactMap { $0 as? SearchHistoryViewController }.first)
  }

  private func historyTable(in history: SearchHistoryViewController) throws -> UITableView {
    try XCTUnwrap(history.view.subviews.compactMap { $0 as? UITableView }.first)
  }

  private func descendants<T: UIView>(of type: T.Type, in view: UIView) -> [T] {
    view.subviews.flatMap { child in
      (child as? T).map { [$0] } ?? descendants(of: type, in: child)
    }
  }
}

private final class HistoryOnlyFrameworkStub: MWMSearchFrameworkHelper {
  static var queries: [String] = []
  static var categoryRequests = 0
  static var clearRequests = 0

  override class func searchCategories() -> [String] {
    categoryRequests += 1
    return ["cafe"]
  }

  override class func lastSearchQueries() -> [String] { queries }

  override class func clearSearchHistory() {
    clearRequests += 1
    queries = []
  }
}

private final class HistoryOnlyDelegateSpy: NSObject, SearchTabViewControllerDelegate {
  var query: SearchQuery?
  weak var scrolledView: UIScrollView?

  func searchTabController(_: SearchTabViewController, didSearch query: SearchQuery) {
    self.query = query
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    scrolledView = scrollView
  }

  func scrollViewWillEndDragging(_: UIScrollView, withVelocity _: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
    targetContentOffset.pointee = .zero
  }
}

private final class WeatherEntryInfoStub: PlacePageInfoData {
  override var latitude: Double { 24.7136 }
  override var longitude: Double { 46.6753 }
  override var phones: [PlacePagePhone] { [] }
}

private final class ShortPlacePageLayout: IPlacePageLayout {
  weak var presenter: PlacePagePresenterProtocol?
  let headerViewController: PlacePageHeaderViewController
  private let contentViewController = UIViewController()

  init(storyboard: UIStoryboard) {
    headerViewController = storyboard.instantiateViewController(ofType: PlacePageHeaderViewController.self)
    contentViewController.view.heightAnchor.constraint(equalToConstant: 180).isActive = true
  }

  var headerViewControllers: [UIViewController] { [headerViewController] }
  var bodyViewControllers: [UIViewController] { [contentViewController] }
  var actionBar: ActionBarViewController? { nil }
  var navigationBar: UIViewController? { nil }

  func calculateSteps(inScrollView scrollView: UIScrollView, compact _: Bool) -> [PlacePageState] {
    [.closed(-scrollView.bounds.height), .preview(80 - scrollView.bounds.height), .full]
  }
}
