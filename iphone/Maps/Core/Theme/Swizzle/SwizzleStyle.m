#import "SwizzleStyle.h"
#import "SwizzleRuntime.h"
#import <UIKit/UIKit.h>
#import "objc/message.h"
#import "objc/runtime.h"

@implementation SwizzleStyle

+ (void)swizzle
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    // Each class needs its own alias for the original implementation. A UIKit
    // override can call super, whose hook must not dispatch back to that alias.
    [SwizzleStyle swizzle:[UISearchBar class]
                    from:@selector(didMoveToWindow)
                      to:NSSelectorFromString(@"sw_searchBarDidMoveToWindow")];
    [SwizzleStyle swizzle:[UITextField class]
                    from:@selector(didMoveToWindow)
                      to:NSSelectorFromString(@"sw_textFieldDidMoveToWindow")];
    [SwizzleStyle swizzle:[UIView class]
                    from:@selector(didMoveToWindow)
                      to:NSSelectorFromString(@"sw_viewDidMoveToWindow")];
  });
}

+ (void)swizzle:(Class)forClass from:(SEL)original to:(SEL)new
{
  if (!MWMSwizzleInstanceMethods(forClass, original, new))
  {
    [NSException raise:NSInternalInconsistencyException
                format:@"Cannot install theme hook for %@", NSStringFromClass(forClass)];
  }
}

@end
