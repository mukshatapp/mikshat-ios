#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface MWMSearchFrameworkHelper : NSObject

+ (NSArray<NSString *> *)searchCategories;

+ (BOOL)isSearchHistoryEmpty;
+ (BOOL)isLanguageSupported:(NSString *)languageCode;
+ (NSArray<NSString *> *)lastSearchQueries;
+ (void)clearSearchHistory;
+ (void)showHistoryLocation:(CLLocationCoordinate2D)coordinate title:(NSString *)title;
+ (CGPoint)mercatorPointForCoordinate:(CLLocationCoordinate2D)coordinate NS_SWIFT_NAME(mercatorPoint(for:));

@end

NS_ASSUME_NONNULL_END
