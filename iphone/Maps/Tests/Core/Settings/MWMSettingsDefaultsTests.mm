#import <XCTest/XCTest.h>

#import <CoreApi/MWMTypes.h>
#import "MWMSettings.h"

#include "platform/settings.hpp"

#include <optional>
#include <string_view>

namespace
{
NSString * const kAutoNightModeOff = @"AutoNightModeOff";
NSString * const kThemeMode = @"ThemeMode";

std::optional<bool> ReadPreference(std::string_view key)
{
  bool value;
  if (settings::Get(key, value))
    return value;
  return std::nullopt;
}

void RestorePreference(std::string_view key, std::optional<bool> value)
{
  if (value)
    settings::Set(key, *value);
  else
    settings::Delete(key);
}

void OnMainThread(void (^action)(void))
{
  if (NSThread.isMainThread)
    action();
  else
    dispatch_sync(dispatch_get_main_queue(), action);
}
}  // namespace

@interface MWMSettingsDefaultsTests : XCTestCase
{
  id m_autoNightModeOff;
  id m_themeMode;
  std::optional<bool> m_perspective;
  std::optional<bool> m_autoZoom;
  std::optional<bool> m_buildings;
}
@end

@implementation MWMSettingsDefaultsTests

- (void)setUp
{
  [super setUp];
  auto defaults = NSUserDefaults.standardUserDefaults;
  m_autoNightModeOff = [defaults objectForKey:kAutoNightModeOff];
  m_themeMode = [defaults objectForKey:kThemeMode];
  m_perspective = ReadPreference("Allow3d");
  m_autoZoom = ReadPreference("AutoZoom");
  m_buildings = ReadPreference("Buildings3d");

  [defaults removeObjectForKey:kAutoNightModeOff];
  [defaults removeObjectForKey:kThemeMode];
  settings::Delete("Allow3d");
  settings::Delete("AutoZoom");
  settings::Delete("Buildings3d");
}

- (void)tearDown
{
  auto defaults = NSUserDefaults.standardUserDefaults;
  if (m_autoNightModeOff)
    [defaults setObject:m_autoNightModeOff forKey:kAutoNightModeOff];
  else
    [defaults removeObjectForKey:kAutoNightModeOff];
  if (m_themeMode)
    [defaults setObject:m_themeMode forKey:kThemeMode];
  else
    [defaults removeObjectForKey:kThemeMode];

  // Restore the live engine as well as the exact pre-test persisted state.
  OnMainThread(^{
    [MWMSettings setPerspectiveViewEnabled:m_perspective.value_or(false)];
    [MWMSettings setAutoZoomEnabled:m_autoZoom.value_or(false)];
  });
  RestorePreference("Allow3d", m_perspective);
  RestorePreference("AutoZoom", m_autoZoom);
  RestorePreference("Buildings3d", m_buildings);
  [super tearDown];
}

- (void)testFreshInstallUsesLightAppearanceAndDisabledMapDefaults
{
  [MWMSettings applyMikshatMapDefaults];

  XCTAssertEqual([MWMSettings theme], MWMThemeDay);
  XCTAssertFalse([MWMSettings perspectiveViewEnabled]);
  XCTAssertFalse([MWMSettings autoZoomEnabled]);
  XCTAssertFalse([MWMSettings map3dBuildingsEnabled]);
}

- (void)testExistingNavigationChoicesSurviveInitialization
{
  for (bool enabled : {false, true})
  {
    settings::Set("Allow3d", enabled);
    settings::Set("AutoZoom", enabled);
    [MWMSettings applyMikshatMapDefaults];

    XCTAssertEqual([MWMSettings perspectiveViewEnabled], enabled);
    XCTAssertEqual([MWMSettings autoZoomEnabled], enabled);
  }
}

- (void)testExplicitLightAndDarkAppearanceChoicesSurviveInitialization
{
  auto defaults = NSUserDefaults.standardUserDefaults;
  for (MWMTheme theme : {MWMThemeDay, MWMThemeNight})
  {
    [defaults setInteger:theme forKey:kThemeMode];
    [defaults setBool:YES forKey:kAutoNightModeOff];
    [MWMSettings applyMikshatMapDefaults];

    XCTAssertEqual([MWMSettings theme], theme);
  }
}

- (void)testExplicitAutomaticAppearanceSurvivesInitialization
{
  auto defaults = NSUserDefaults.standardUserDefaults;
  [defaults setInteger:MWMThemeAuto forKey:kThemeMode];
  [defaults setBool:NO forKey:kAutoNightModeOff];

  [MWMSettings applyMikshatMapDefaults];

  XCTAssertEqual([MWMSettings theme], MWMThemeAuto);
}

- (void)testLegacyThemePreferenceKeepsItsAutomaticInterpretation
{
  [NSUserDefaults.standardUserDefaults setInteger:MWMThemeNight forKey:kThemeMode];

  [MWMSettings applyMikshatMapDefaults];

  XCTAssertEqual([MWMSettings theme], MWMThemeAuto);
}

- (void)testPreviouslyEnabledBuildingsAreDisabledAndPersisted
{
  settings::Set("Buildings3d", true);

  [MWMSettings applyMikshatMapDefaults];

  auto buildings = ReadPreference("Buildings3d");
  XCTAssertTrue(buildings.has_value());
  XCTAssertFalse(buildings.value_or(true));
  XCTAssertFalse([MWMSettings map3dBuildingsEnabled]);
}

- (void)testHiddenBuildingsSettingCannotBeReenabled
{
  [MWMSettings applyMikshatMapDefaults];
  for (bool perspective : {false, true})
  {
    OnMainThread(^{
      [MWMSettings setPerspectiveViewEnabled:perspective];
      [MWMSettings setMap3dBuildingsEnabled:YES];
    });

    XCTAssertEqual([MWMSettings perspectiveViewEnabled], perspective);
    XCTAssertFalse([MWMSettings map3dBuildingsEnabled]);
    XCTAssertFalse(ReadPreference("Buildings3d").value_or(true));
  }
}

- (void)testLaterLaunchesPreserveNewExplicitNavigationChoices
{
  [MWMSettings applyMikshatMapDefaults];
  OnMainThread(^{
    [MWMSettings setPerspectiveViewEnabled:YES];
    [MWMSettings setAutoZoomEnabled:YES];
  });

  [MWMSettings applyMikshatMapDefaults];
  [MWMSettings applyMikshatMapDefaults];

  XCTAssertTrue([MWMSettings perspectiveViewEnabled]);
  XCTAssertTrue([MWMSettings autoZoomEnabled]);
  XCTAssertFalse([MWMSettings map3dBuildingsEnabled]);
}

- (void)testAutomaticAppearanceCanBeSelectedAfterFreshInstall
{
  [MWMSettings applyMikshatMapDefaults];
  XCTAssertEqual([MWMSettings theme], MWMThemeDay);

  OnMainThread(^{ [MWMSettings setTheme:MWMThemeAuto]; });
  [MWMSettings applyMikshatMapDefaults];

  XCTAssertEqual([MWMSettings theme], MWMThemeAuto);
  XCTAssertEqualObjects([NSUserDefaults.standardUserDefaults objectForKey:kAutoNightModeOff], @NO);
}

@end
