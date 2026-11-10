#import "MWMSideButtonsView.h"
#import "MWMButton.h"
#import "MWMMapViewControlsCommon.h"
#import "SwiftBridge.h"

#include "base/math.hpp"

namespace
{
CGFloat const kLocationButtonSpacingMax = 52;
CGFloat const kLocationButtonSpacingMin = 8;
CGFloat const kButtonsTopOffset = 6;
CGFloat const kButtonsBottomOffset = 6;
}  // namespace

@interface MWMSideButtonsView ()

@property(weak, nonatomic) IBOutlet MWMButton * zoomIn;
@property(weak, nonatomic) IBOutlet MWMButton * zoomOut;
@property(weak, nonatomic) IBOutlet MWMButton * location;

@property(nonatomic) CGRect availableArea;

@end

@implementation MWMSideButtonsView

- (void)awakeFromNib
{
  [super awakeFromNib];
  self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  NSArray<UIButton *> * buttons = @[self.zoomIn, self.zoomOut, self.location];
  NSArray<NSString *> * symbols = @[@"plus", @"minus", @"scope"];
  UIColor * green = [UIColor colorWithRed:22.0/255 green:78.0/255 blue:63.0/255 alpha:1];
  for (NSUInteger index = 0; index < buttons.count; ++index)
  {
    UIButton * button = buttons[index];
    [button setImage:[UIImage systemImageNamed:symbols[index]] forState:UIControlStateNormal];
    button.tintColor = green;
    button.backgroundColor = UIColor.whiteColor;
    button.layer.cornerRadius = button.bounds.size.width / 2;
  }
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat const size = self.superview.bounds.size.width > self.superview.bounds.size.height ? 38 : 52;
  CGFloat const gap = 8;
  self.zoomIn.frame = CGRectMake(0, 0, size, size);
  self.zoomOut.frame = CGRectMake(0, size + gap, size, size);
  self.location.frame = CGRectMake(0, self.zoomHidden ? 0 : 2 * (size + gap), size, size);
  self.bounds = CGRectMake(0, 0, size, self.zoomHidden ? size : 3 * size + 2 * gap);
  for (UIButton * button in @[self.zoomIn, self.zoomOut, self.location])
    button.layer.cornerRadius = size / 2;
  [self layoutXPosition:self.hidden];
  [self layoutYPosition];
}

- (void)layoutXPosition:(BOOL)hidden
{
  if (hidden)
    self.minX = self.superview.bounds.size.width;
  else
  {
    CGFloat const columnWidth = self.superview.bounds.size.width > self.superview.bounds.size.height ? 52 : 68;
    self.maxX = self.superview.bounds.size.width - self.superview.safeAreaInsets.right - 14 - (columnWidth - self.width) / 2;
  }
}

- (void)layoutYPosition
{
  // Independent of the place-card available area: raised sheets cover these controls.
  self.minY = [MikshatHomeControls minimumMapControlsYInView:self.superview];
}

- (void)fadeZoomButtonsShow:(BOOL)show
{
  CGFloat const alpha = show ? 1.0 : 0.0;
  [UIView animateWithDuration:AppConstants.defaultAnimationDuration
                   animations:^{
                     self.zoomIn.alpha = alpha;
                     self.zoomOut.alpha = alpha;
                   }];
}

- (void)fadeLocationButtonShow:(BOOL)show
{
  [UIView animateWithDuration:AppConstants.defaultAnimationDuration
                   animations:^{ self.location.alpha = show ? 1.0 : 0.0; }];
}

// Show/hide zoom and location buttons depending on available vertical space.
- (void)animate
{
  [self layoutYPosition];
}

#pragma mark - Properties

- (void)setZoomHidden:(BOOL)zoomHidden
{
  _zoomHidden = zoomHidden;
  self.zoomIn.hidden = zoomHidden;
  self.zoomOut.hidden = zoomHidden;
  [self setNeedsLayout];
}

- (void)setHidden:(BOOL)hidden animated:(BOOL)animated
{
  if (animated)
  {
    if (self.hidden == hidden)
      return;
    // Side buttons should be visible during any our show/hide anamation.
    // Visibility should be detemined by alpha, not self.hidden.
    self.hidden = NO;
    [UIView animateWithDuration:AppConstants.defaultAnimationDuration
        animations:^{
          self.alpha = hidden ? 0.0 : 1.0;
          [self layoutXPosition:hidden];
        }
        completion:^(BOOL finished) { self.hidden = hidden; }];
  }
  else
  {
    self.hidden = hidden;
  }
}

- (void)updateAvailableArea:(CGRect)frame
{
  if (CGRectIsEmpty(frame))
    return;
  if (CGRectEqualToRect(self.availableArea, frame))
    return;
  // If during our show/hide animation position is changed it is corrupted.
  // Such kind of animation has 2 keys (opacity and position).
  // But there are other animation cases like change of orientation.
  // So we can use condition below:
  // if (self.layer.animationKeys.count != 2)
  // More elegant way is to check if x values are changed.
  // If no - there is no need to update self x values.
  if (self.availableArea.origin.x != frame.origin.x || self.availableArea.size.width != frame.size.width)
  {
    self.availableArea = frame;
    [self layoutXPosition:self.hidden];
  }
  else
    self.availableArea = frame;
  [self setNeedsLayout];
}

- (CGFloat)availableHeight
{
  return self.availableArea.size.height - kButtonsTopOffset - kButtonsBottomOffset;
}

- (CGFloat)topBound
{
  return self.availableArea.origin.y + kButtonsTopOffset;
}
- (CGFloat)bottomBound
{
  auto const area = self.availableArea;
  return area.origin.y + area.size.height - kButtonsBottomOffset;
}

@end
