@testable import Organic_Maps__Debug_
import CoreLocation
import XCTest
import UIKit

final class PlacePageSourceMetadataTests: XCTestCase {
  // Raw description and coordinates verified in desert-ksa-south.mwm, feature 25725.
  private let copyright = "الحقوق محفوظة لتطبيق خرائط الصحراء"

  func test_SourceCopyrightDescriptionIsOmitted() {
    XCTAssertNil(PlacePageSourceMetadata.descriptionForDisplay(copyright))
    XCTAssertNil(PlacePageSourceMetadata.descriptionForDisplay("\n  الحقوق محفوظة لتطبيق\nخرائط الصحراء  "))
    XCTAssertNil(PlacePageSourceMetadata.descriptionForDisplay(nil))
  }

  func test_RealPlaceDescriptionsRemainUnchanged() {
    for description in ["قمة جبلية قرب الوادي", "OpenStreetMap survey point", copyright + "، والموقع مفتوح للزوار"] {
      XCTAssertEqual(PlacePageSourceMetadata.descriptionForDisplay(description), description)
    }
  }

  func test_VerifiedProviderWebsiteEndpointsAreOmitted() {
    for website in ["https://knaree.com/ksa", "http://knaree.com/ksa/", "knaree.com/ksa",
                    "https://www.KNAREE.com/ksa?source=map", "//knaree.com/ksa",
                    "desertsa.com", "https://desertsa.com", "http://www.desertsa.com/"] {
      XCTAssertNil(PlacePageSourceMetadata.websiteForDisplay(website), website)
    }
    XCTAssertNil(PlacePageSourceMetadata.websiteForDisplay(nil))
  }

  func test_BusinessWebsitesAndOtherProviderPathsRemainUnchanged() {
    for website in ["https://example.com/ksa", "https://kharee.com/ksa", "https://knaree.com/ksa/hotel",
                    "https://knaree.com/ksa-restaurant", "https://knaree.com.example.com/ksa",
                    "https://desertsa.com/cafe", "https://example.com/?site=knaree.com/ksa",
                    "https://knaree.com@restaurant.example/ksa", "ftp://knaree.com/ksa"] {
      XCTAssertEqual(PlacePageSourceMetadata.websiteForDisplay(website), website)
    }
  }

  func test_CopyrightOmitsWholeDescriptionSectionAndPreservesPlaceData() {
    prepareTheme()
    for (description, expectedSectionCount) in [(copyright, 1), ("قمة جبلية قرب الوادي", 2)] {
      let data = SourceMetadataPlaceDataStub(description: description)
      let interactor = PlacePageInteractor(data: data)
      let layout = PlacePageCommonLayout(interactor: interactor,
                                         storyboard: UIStoryboard.instance(.placePage),
                                         data: data)
      // The bookmark editor remains; only genuine descriptions add a second section.
      let sections = layout.bodyViewControllers.compactMap { $0 as? PlacePageExpandableDetailsSectionViewController }
      XCTAssertEqual(sections.count, expectedSectionCount)
      XCTAssertEqual(data.osmDescription, description)
      XCTAssertEqual(data.previewData.title, "جبال القصيعة")
      XCTAssertEqual(data.locationCoordinate.latitude, 23.92508767081141)
      XCTAssertEqual(data.locationCoordinate.longitude, 47.2388469222102)
    }
  }

  func test_SourceWebsiteRowIsAbsentAndWeatherStillWorks() throws {
    for website in ["https://knaree.com/ksa", "desertsa.com"] {
      let data = SourceMetadataInfoDataStub(website: website)
      let controller = makeInfoController(data: data)
      var weatherRequests = 0
      controller.didTapWeather = { weatherRequests += 1 }
      controller.loadViewIfNeeded()

      let rows = controller.stackView.arrangedSubviews.compactMap { $0 as? InfoItemView }
      XCTAssertEqual(rows.count, 1)
      let weather = try XCTUnwrap(rows.first)
      XCTAssertEqual(weather.accessibilityIdentifier, "placePage.weather")
      weather.infoLabelTapHandler?()
      XCTAssertEqual(weatherRequests, 1)
      XCTAssertEqual(data.website, website)
    }
  }

  func test_BusinessWebsiteRowStillOpensAndCopiesOriginalURL() throws {
    let website = "https://restaurant.example/menu/"
    let data = SourceMetadataInfoDataStub(website: website)
    let controller = makeInfoController(data: data)
    let delegate = SourceMetadataInfoDelegateSpy()
    controller.delegate = delegate
    controller.loadViewIfNeeded()

    let row = try XCTUnwrap(controller.stackView.arrangedSubviews.compactMap { $0 as? InfoItemView }.first)
    XCTAssertEqual(row.textLabel.text, "restaurant.example/menu")
    row.infoLabelTapHandler?()
    row.infoLabelLongPressHandler?()
    XCTAssertEqual(delegate.websiteRequests, 1)
    XCTAssertEqual(delegate.copies, [website])
    XCTAssertEqual(data.website, website)
  }

  private func makeInfoController(data: PlacePageInfoData) -> PlacePageInfoViewController {
    prepareTheme()
    let controller = UIStoryboard.instance(.placePage).instantiateViewController(ofType: PlacePageInfoViewController.self)
    controller.placePageInfoData = data
    return controller
  }

  private func prepareTheme() {
    if !StyleManager.shared.hasTheme() {
      StyleManager.shared.setTheme(MainTheme())
    }
  }
}

private final class SourceMetadataPlaceDataStub: PlacePageData {
  private let descriptionValue: String
  private let preview = SourceMetadataPreviewDataStub()

  init(description: String) {
    descriptionValue = description
    super.init(trackInfo: TrackInfo.empty(), elevationInfo: nil)
  }

  override var objectType: PlacePageObjectType { .POI }
  override var previewData: PlacePagePreviewData { preview }
  override var osmDescription: String? { descriptionValue }
  override var wikiDescriptionHtml: String? { "<p>Wikipedia section stays hidden</p>" }
  override var locationCoordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: 23.92508767081141, longitude: 47.2388469222102)
  }
}

private final class SourceMetadataPreviewDataStub: PlacePagePreviewData {
  override var title: String? { "جبال القصيعة" }
  override var subtitle: String? { "قمة" }
}

private final class SourceMetadataInfoDataStub: PlacePageInfoData {
  private let websiteValue: String

  init(website: String) {
    websiteValue = website
    super.init()
  }

  override var website: String? { websiteValue }
  override var phones: [PlacePagePhone] { [] }
}

private final class SourceMetadataInfoDelegateSpy: PlacePageInfoViewControllerDelegate {
  var websiteRequests = 0
  var copies: [String] = []
  var shouldShowOpenInApp: Bool { false }

  func didPressWebsite() { websiteRequests += 1 }
  func didCopy(_ content: String) { copies.append(content) }
  func didPressCall(to phone: PlacePagePhone) {}
  func didPressHeritageWebsite() {}
  func didPressWebsiteMenu() {}
  func didPressWikipedia() {}
  func didPressWikimediaCommons() {}
  func didPressFacebook() {}
  func didPressInstagram() {}
  func didPressTwitter() {}
  func didPressVk() {}
  func didPressLine() {}
  func didPressEmail() {}
  func didPressOpenInApp(from sourceView: UIView) {}
  func didSelectPublicTransportRoute(scrollAnchor: UIView) {}
}
