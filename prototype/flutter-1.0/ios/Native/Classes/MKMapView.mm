#import "MKMapView.h"
#import "MetalContextFactory.h"
#include "Engine.hpp"
#include "drape_frontend/visual_params.hpp"
#include "drape_frontend/user_event_stream.hpp"
#include "geometry/mercator.hpp"

@implementation MKMapView
{
  drape_ptr<MetalContextFactory> m_factory;
  CGSize m_lastSize;
}
+ (Class)layerClass { return CAMetalLayer.class; }
- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame]))
  {
    self.multipleTouchEnabled = YES;
    self.contentScaleFactor = UIScreen.mainScreen.nativeScale;
    CAMetalLayer * layer = (CAMetalLayer *)self.layer;
    layer.device = MTLCreateSystemDefaultDevice();
    layer.opaque = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(background)
      name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(foreground)
      name:UIApplicationWillEnterForegroundNotification object:nil];
  }
  return self;
}
- (UIView *)view { return self; }
- (void)layoutSubviews
{
  [super layoutSubviews];
  CGSize const pixels = CGSizeMake(self.bounds.size.width * self.contentScaleFactor,
                                  self.bounds.size.height * self.contentScaleFactor);
  if (pixels.width < 1 || pixels.height < 1 || CGSizeEqualToSize(pixels, m_lastSize)) return;
  m_lastSize = pixels;
  auto & framework = MukshatFramework();
  if (!m_factory)
  {
    m_factory = make_unique_dp<MetalContextFactory>((CAMetalLayer *)self.layer,
      m2::PointU(static_cast<uint32_t>(pixels.width), static_cast<uint32_t>(pixels.height)));
    Framework::DrapeCreationParams params;
    params.m_apiVersion = dp::ApiVersion::Metal;
    params.m_surfaceWidth = pixels.width;
    params.m_surfaceHeight = pixels.height;
    params.m_visualScale = df::CSF2VS(self.contentScaleFactor);
    params.m_hints.m_isFirstLaunch = false;
    framework.CreateDrapeEngine(make_ref(m_factory), std::move(params));
    m_factory->SetPresentAvailable(true);
    framework.SetViewportCenter(mercator::FromLatLon(24.7136,46.6753),12,false);
  }
  else framework.OnSize(pixels.width,pixels.height);
}
- (void)background { if (m_factory) m_factory->SetPresentAvailable(false); }
- (void)foreground { if (m_factory) m_factory->SetPresentAvailable(true); }
- (void)sendTouches:(NSSet<UITouch *> *)touches type:(df::TouchEvent::ETouchType)type
{
  df::TouchEvent event; event.SetTouchType(type);
  NSUInteger index=0;
  for (UITouch * touch in touches)
  {
    CGPoint point=[touch locationInView:self];
    df::Touch item; item.m_id=reinterpret_cast<int64_t>((__bridge void *)touch);
    item.m_location=m2::PointF(point.x*self.contentScaleFactor,point.y*self.contentScaleFactor);
    if (index++==0) {event.SetFirstTouch(item);event.SetFirstMaskedPointer(0);}
    else {event.SetSecondTouch(item);event.SetSecondMaskedPointer(1);break;}
  }
  MukshatFramework().TouchEvent(event);
}
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {[self sendTouches:event.allTouches type:df::TouchEvent::TOUCH_DOWN];}
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {[self sendTouches:event.allTouches type:df::TouchEvent::TOUCH_MOVE];}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {[self sendTouches:event.allTouches type:df::TouchEvent::TOUCH_UP];}
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {[self sendTouches:event.allTouches type:df::TouchEvent::TOUCH_CANCEL];}
- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  MukshatFramework().DestroyDrapeEngine();
  m_factory.reset();
}
@end
@implementation MKMapFactory
- (NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame viewIdentifier:(int64_t)viewId arguments:(id)args
{ return [[MKMapView alloc] initWithFrame:frame]; }
@end
