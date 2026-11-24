#import "MWMSearchFrameworkHelper.h"

#include "platform/preferred_languages.hpp"
#include "search/displayed_categories.hpp"

#include "Framework.h"
#include "geometry/mercator.hpp"

@implementation MWMSearchFrameworkHelper

+ (NSArray<NSString *> *)searchCategories
{
  NSMutableArray * result = [NSMutableArray array];
  auto const & categories = GetFramework().GetDisplayedCategories().GetKeys();
  for (auto const & item : categories)
    [result addObject:@(item.c_str())];
  return [result copy];
}

+ (BOOL)isSearchHistoryEmpty
{
  return GetFramework().GetSearchAPI().GetLastSearchQueries().empty();
}

+ (BOOL)isLanguageSupported:(NSString *)languageCode
{
  return search::DisplayedCategories::IsLanguageSupported(languageCode.UTF8String);
}

+ (NSArray<NSString *> *)lastSearchQueries
{
  NSMutableArray * result = [NSMutableArray array];
  auto const & queries = GetFramework().GetSearchAPI().GetLastSearchQueries();
  for (auto const & item : queries)
    [result addObject:@(item.second.c_str())];
  return [result copy];
}

+ (void)clearSearchHistory
{
  GetFramework().GetSearchAPI().ClearSearchHistory();
}

+ (void)showHistoryLocation:(CLLocationCoordinate2D)coordinate title:(NSString *)title
{
  if (!CLLocationCoordinate2DIsValid(coordinate))
    return;
  GetFramework().ShowPointSelection(mercator::FromLatLon(coordinate.latitude, coordinate.longitude), title.UTF8String);
}

+ (CGPoint)mercatorPointForCoordinate:(CLLocationCoordinate2D)coordinate
{
  auto const point = mercator::FromLatLon(coordinate.latitude, coordinate.longitude);
  return CGPointMake(point.x, point.y);
}

@end
