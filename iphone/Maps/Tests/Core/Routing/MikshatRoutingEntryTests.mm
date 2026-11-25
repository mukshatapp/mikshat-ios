#import <XCTest/XCTest.h>

#import "EAGLView.h"
#import "MWMActionBarButton.h"
#import "MWMNavigationDashboardManager.h"
#import "MWMRoutePoint.h"
#import "MWMRouter.h"
#import "MapViewController.h"

#import <CoreApi/Framework.h>

#include "map/everywhere_search_params.hpp"
#include "map/place_page_info.hpp"
#include "platform/country_file.hpp"

namespace
{
ms::LatLon const kStart(24.7136, 46.6753);
ms::LatLon const kFinish(24.7194, 46.6766);

void OnMainThread(void (^action)(void))
{
  if (NSThread.isMainThread)
    action();
  else
    dispatch_sync(dispatch_get_main_queue(), action);
}

MWMActionBarButton * FindGoToButton(UIView * view)
{
  if ([view isKindOfClass:MWMActionBarButton.class] &&
      ((MWMActionBarButton *)view).type == MWMActionBarButtonTypeRouteTo)
    return (MWMActionBarButton *)view;
  for (UIView * child in view.subviews)
    if (auto * button = FindGoToButton(child))
      return button;
  return nil;
}

UIControl * FindTouchControl(UIView * view)
{
  if ([view isKindOfClass:UIControl.class])
    return (UIControl *)view;
  for (UIView * child in view.subviews)
    if (auto * control = FindTouchControl(child))
      return control;
  return nil;
}
}  // namespace

@interface MikshatRoutingEntryTestCase : XCTestCase
@property(nonatomic) MWMRouterType previousRouterType;
- (void)selectMapPoint;
- (void)selectSearchResult;
- (void)tapGoTo;
- (void)addExplicitStart;
- (void)assertSelectedDestination;
- (void)assertRouteReady;
@end

@implementation MikshatRoutingEntryTestCase

- (void)setUp
{
  [super setUp];
  OnMainThread(^{
    auto * map = MapViewController.sharedController;
    [map loadViewIfNeeded];
    XCTAssertNotNil(map);
    self.previousRouterType = MWMRouter.type;
    [MWMRouter stopRouting];
    XCTestExpectation * closed = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id, NSDictionary *)
        {
          for (UIViewController * controller in map.childViewControllers)
          {
            NSString * name = NSStringFromClass(controller.class);
            if ([name containsString:@"NavigationDashboardViewController"] ||
                [name containsString:@"PlacePageViewController"])
              return NO;
          }
          return YES;
        }]
                   object:nil];
    [self waitForExpectations:@[closed] timeout:5];
    [MWMRouter enableAutoAddLastLocation:NO];
    [MWMRouter setType:MWMRouterTypeRuler];
  });
}

- (void)tearDown
{
  OnMainThread(^{
    GetFramework().GetSearchAPI().CancelAllSearches();
    [MWMRouter stopRouting];
    [MWMRouter setType:self.previousRouterType];
    [MWMRouter enableAutoAddLastLocation:YES];
  });
  [super tearDown];
}

- (void)selectMapPoint
{
  place_page::BuildInfo selection;
  selection.m_source = place_page::BuildInfo::Source::User;
  selection.m_mercator = mercator::FromLatLon(kFinish);
  selection.m_match = place_page::BuildInfo::Match::Nothing;
  // Enter the native tap-selection handler with an exact map coordinate.
  GetFramework().BuildAndSetPlacePageInfo(selection);
}

- (void)selectSearchResult
{
  if ([NSProcessInfo.processInfo.arguments containsObject:@"-IsTests"])
  {
    // This profile deliberately omits Drape, which normally initializes search's viewport.
    auto const point = mercator::FromLatLon(kFinish);
    GetFramework().GetSearchAPI().OnViewportChanged(m2::RectD(point.x - 0.1, point.y - 0.1,
                                                           point.x + 0.1, point.y + 0.1));
  }
  auto result = std::make_shared<std::optional<search::Result>>();
  XCTestExpectation * completed = [self expectationWithDescription:@"Native coordinate search completed"];
  search::EverywhereSearchParams params;
  params.m_query = "24.7194,46.6766";
  params.m_inputLocale = "en";
  params.m_onResults = [result, completed](search::Results results)
  {
    for (auto const & candidate : results)
      if (!candidate.IsSuggest())
      {
        *result = candidate;
        break;
      }
    if (results.IsEndMarker())
      [completed fulfill];
  };
  XCTAssertTrue(GetFramework().GetSearchAPI().SearchEverywhere(std::move(params)));
  [self waitForExpectations:@[completed] timeout:20];
  XCTAssertTrue(result->has_value());
  if (!result->has_value())
    return;
  // Search result selection enters Framework::ShowSearchResult in production.
  GetFramework().ShowSearchResult(**result, false /* animation */);
}

- (void)tapGoTo
{
  auto * map = MapViewController.sharedController;
  XCTestExpectation * attached = [[XCTNSPredicateExpectation alloc]
      initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id, NSDictionary *)
      { return FindGoToButton(map.view) != nil; }]
                 object:nil];
  [self waitForExpectations:@[attached] timeout:5];
  MWMActionBarButton * button = FindGoToButton(map.view);
  UIControl * control = FindTouchControl(button);
  XCTAssertNotNil(control);
  XCTAssertTrue(control.enabled);
  // Exercise the actual nib action, action-bar delegate and place-page manager.
  [control sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)addExplicitStart
{
  auto const point = mercator::FromLatLon(kStart);
  [MWMRouter addPoint:[[MWMRoutePoint alloc] initWithCGPoint:CGPointMake(point.x, point.y)
                                                   title:@"Fixed origin"
                                                subtitle:nil
                                                    type:MWMRoutePointTypeStart
                                       intermediateIndex:0]];
}

- (void)assertSelectedDestination
{
  XCTAssertNotNil(MWMRouter.finishPoint);
  XCTAssertEqualWithAccuracy(MWMRouter.finishPoint.latitude, kFinish.m_lat, 0.000001);
  XCTAssertEqualWithAccuracy(MWMRouter.finishPoint.longitude, kFinish.m_lon, 0.000001);
}

- (void)assertRouteReady
{
  XCTestExpectation * ready = [[XCTNSPredicateExpectation alloc]
      initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id, NSDictionary *)
      { return MWMNavigationDashboardManager.sharedManager.state == MWMNavigationDashboardStateReady; }]
                 object:nil];
  [self waitForExpectations:@[ready] timeout:60];
  XCTAssertTrue(MWMRouter.isRouteValid);
  XCTAssertEqual(MWMRouter.type, MWMRouterTypeRuler);
  [self assertSelectedDestination];
}

@end

@interface MikshatRoutingEntryTests : MikshatRoutingEntryTestCase
@end

@implementation MikshatRoutingEntryTests

- (void)testMapSelectionGoToWithoutOriginKeepsDestinationAndShowsNativePrepare
{
  OnMainThread(^{
    [self selectMapPoint];
    [self tapGoTo];
    [self assertSelectedDestination];
    XCTAssertNil(MWMRouter.startPoint);
    XCTAssertEqual(MWMNavigationDashboardManager.sharedManager.state, MWMNavigationDashboardStatePrepare);
    XCTAssertNotNil(MWMNavigationDashboardManager.sharedManager.availableAreaView.superview);
  });
}

- (void)testSearchSelectionGoToWithoutOriginKeepsDestinationAndShowsNativePrepare
{
  OnMainThread(^{
    [self selectSearchResult];
    [self tapGoTo];
    [self assertSelectedDestination];
    XCTAssertNil(MWMRouter.startPoint);
    XCTAssertEqual(MWMNavigationDashboardManager.sharedManager.state, MWMNavigationDashboardStatePrepare);
    XCTAssertNotNil(MWMNavigationDashboardManager.sharedManager.availableAreaView.superview);
  });
}

- (void)testMapSelectionGoToBuildsInternalRulerFromExplicitOrigin
{
  OnMainThread(^{
    [self addExplicitStart];
    [self selectMapPoint];
    [self tapGoTo];
    [self assertRouteReady];
    XCTAssertEqualObjects(MWMRouter.startPoint.title, @"Fixed origin");
  });
}

- (void)testSearchSelectionGoToBuildsInternalRulerFromExplicitOrigin
{
  OnMainThread(^{
    [self addExplicitStart];
    [self selectSearchResult];
    [self tapGoTo];
    [self assertRouteReady];
    XCTAssertEqualObjects(MWMRouter.startPoint.title, @"Fixed origin");
  });
}

@end

// Run this class separately with a normal renderer and the verified Saudi North
// fixture installed in the app container. Missing prerequisites fail the pass.
@interface MikshatVehicleRoutingEntryTests : MikshatRoutingEntryTestCase
@end

@implementation MikshatVehicleRoutingEntryTests

- (void)assertVehiclePrerequisites
{
  XCTAssertTrue([NSProcessInfo.processInfo.arguments containsObject:@"-MikshatRequireRenderer"]);
  XCTAssertFalse([NSProcessInfo.processInfo.arguments containsObject:@"-IsTests"]);
  auto * map = MapViewController.sharedController;
  XCTestExpectation * renderer = [[XCTNSPredicateExpectation alloc]
      initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id, NSDictionary *)
      {
        auto * window = map.view.window;
        return UIApplication.sharedApplication.applicationState == UIApplicationStateActive && window.isKeyWindow &&
               !window.isHidden && map.mapView.drapeEngineCreated && map.mapView.graphicContextInitialized;
      }]
                 object:nil];
  [self waitForExpectations:@[renderer] timeout:30];
  auto & framework = GetFramework();
  XCTAssertNotEqual(framework.GetDrapeEngine(), nullptr);
  XCTAssertEqualObjects(NSStringFromClass(map.mapView.layer.class), @"CAMetalLayer");
  XCTAssertTrue(framework.GetDataSource()
                    .GetMwmIdByCountryFile(platform::CountryFile("Saudi Arabia_North"))
                    .IsAlive());
  XCTAssertTrue(framework.GetDataSource()
                    .GetMwmIdByCountryFile(platform::CountryFile("Saudi Arabia_South"))
                    .IsAlive(), @"The actual Riyadh route requires the official South map");
  XCTAssertTrue(framework.GetDataSource()
                    .GetMwmIdByCountryFile(platform::CountryFile("desert-ksa-north"))
                    .IsAlive(), @"Vehicle routing must coexist with the default supplementary maps");
  XCTAssertTrue(framework.GetDataSource()
                    .GetMwmIdByCountryFile(platform::CountryFile("desert-ksa-south"))
                    .IsAlive(), @"The actual Riyadh route must coexist with the default South supplementary map");
  [MWMRouter setType:MWMRouterTypeVehicle];
  [self addExplicitStart];
}

- (void)assertVehicleRouteReady
{
  XCTestExpectation * ready = [[XCTNSPredicateExpectation alloc]
      initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id, NSDictionary *)
      { return MWMNavigationDashboardManager.sharedManager.state == MWMNavigationDashboardStateReady; }]
                 object:nil];
  [self waitForExpectations:@[ready] timeout:60];
  XCTAssertEqual(MWMRouter.type, MWMRouterTypeVehicle);
  XCTAssertTrue(MWMRouter.isRouteValid);
  XCTAssertFalse(MWMRouter.isOnRoute);
  [self assertSelectedDestination];
}

- (void)testMapSelectionGoToBuildsVehicleRouteWithSaudiMapAndRenderer
{
  OnMainThread(^{
    [self assertVehiclePrerequisites];
    [self selectMapPoint];
    [self tapGoTo];
    [self assertVehicleRouteReady];
  });
}

- (void)testSearchSelectionGoToBuildsVehicleRouteWithSaudiMapAndRenderer
{
  OnMainThread(^{
    [self assertVehiclePrerequisites];
    [self selectSearchResult];
    [self tapGoTo];
    [self assertVehicleRouteReady];
  });
}

@end
