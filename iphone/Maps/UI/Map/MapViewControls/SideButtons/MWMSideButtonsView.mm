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
@property(nonatomic, strong) NSLayoutConstraint * widthConstraint;
@property(nonatomic, strong) NSLayoutConstraint * heightConstraint;

@end

@implementation MWMSideButtonsView

- (void)awakeFromNib
{
  [super awakeFromNib];
  self.autoresizingMask = UIViewAutoresizingNone;
  self.translatesAutoresizingMaskIntoConstraints = NO;
  self.widthConstraint = [self.widthAnchor constraintEqualToConstant:52];
  self.heightConstraint = [self.heightAnchor constraintEqualToConstant:172];
  [NSLayoutConstraint activateConstraints:@[self.widthConstraint, self.heightConstraint]];
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

- (void)didMoveToSuperview
{
  [super didMoveToSuperview];
  if (self.superview)
    [MikshatHomeControls attachMapControls:self];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  if (!self.superview)
    return;
  CGSize const viewport = self.window ? self.window.bounds.size : self.superview.bounds.size;
  CGFloat const size = viewport.width > viewport.height ? 44 : 52;
  CGFloat const gap = 8;
  CGFloat const height = self.zoomHidden ? size : 3 * size + 2 * gap;
  if (self.widthConstraint.constant != size)
    self.widthConstraint.constant = size;
  if (self.heightConstraint.constant != height)
    self.heightConstraint.constant = height;
  self.zoomIn.frame = CGRectMake(0, 0, size, size);
  self.zoomOut.frame = CGRectMake(0, size + gap, size, size);
  self.location.frame = CGRectMake(0, self.zoomHidden ? 0 : 2 * (size + gap), size, size);
  for (UIButton * button in @[self.zoomIn, self.zoomOut, self.location])
    button.layer.cornerRadius = size / 2;
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
  [self setNeedsLayout];
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
  // Sheet movement must not change the anchors below the Qibla button.
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
