#import "MKOrganicPlugin.h"
#import "MKMapView.h"
#import <CoreLocation/CoreLocation.h>
#include "Engine.hpp"
#include "map/gps_tracker.hpp"
#include "map/everywhere_search_params.hpp"
#include "map/routing_mark.hpp"
#include "platform/platform.hpp"
#include "platform/preferred_languages.hpp"
#include "platform/settings.hpp"
#include "geometry/mercator.hpp"
#include "routing/route.hpp"
#include "search/result.hpp"

@interface MKOrganicPlugin () <CLLocationManagerDelegate>
@property(nonatomic,copy) FlutterEventSink events;
@property(nonatomic,strong) CLLocationManager * gps;
@property(nonatomic,strong) CLLocation * location;
@property(nonatomic,strong) CLLocation * previous;
@property(nonatomic,strong) NSMutableData * journal;
@property(nonatomic,copy) NSString * journalPath;
@property(nonatomic,copy) NSString * targetName;
@property(nonatomic,copy) NSString * mode;
@property(nonatomic) double targetLat;
@property(nonatomic) double targetLon;
@property(nonatomic) double trackDistance;
@property(nonatomic) NSUInteger trackPoints;
@property(nonatomic) int64_t queryId;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL recording;
@property(nonatomic) BOOL navigating;
@end
@implementation MKOrganicPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar
{
  MKOrganicPlugin * plugin=[[self alloc] init];
  FlutterMethodChannel * methods=[FlutterMethodChannel methodChannelWithName:@"com.mikshat.prototype/engine" binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:plugin channel:methods];
  FlutterEventChannel * events=[FlutterEventChannel eventChannelWithName:@"com.mikshat.prototype/events" binaryMessenger:registrar.messenger];
  [events setStreamHandler:plugin];
  [registrar registerViewFactory:[[MKMapFactory alloc] init] withId:@"com.mikshat.prototype/map"];
}
- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {self.events=events;return nil;}
- (FlutterError *)onCancelWithArguments:(id)arguments {self.events=nil;return nil;}
- (void)emit:(NSDictionary *)data
{
  dispatch_async(dispatch_get_main_queue(),^{if(self.events)self.events(data);});
}
- (NSString *)tracksDirectory
{
  NSString * dir=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"prototype-tracks"];
  [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];return dir;
}
- (void)initialize:(FlutterResult)result
{
  if(self.ready) {result(nil);return;}
  NSString * bundle=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"MukshatData.bundle"];
  NSString * documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
    NSError * error=nil;
    NSString * version=[documents stringByAppendingPathComponent:@"260714"];
    [NSFileManager.defaultManager createDirectoryAtPath:version withIntermediateDirectories:YES attributes:nil error:&error];
    for(NSString * name in @[@"Saudi Arabia_North.mwm",@"Saudi Arabia_South.mwm"])
    {
      NSString * destination=[version stringByAppendingPathComponent:name];
      if(![NSFileManager.defaultManager fileExistsAtPath:destination])
        [NSFileManager.defaultManager copyItemAtPath:[[bundle stringByAppendingPathComponent:@"regions"] stringByAppendingPathComponent:name] toPath:destination error:&error];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if(error) {result([FlutterError errorWithCode:@"MAP_INSTALL" message:error.localizedDescription details:nil]);return;}
      GetPlatform().SetResourceDir(bundle.UTF8String);
      languages::SetPreferredLanguageOverride("ar");
      auto & framework=MukshatFramework();
      framework.RegisterAllMaps();
      framework.SetMapStyle(MapStyleOutdoorsLight);
      framework.GetBookmarkManager().LoadBookmarks();
      self.gps=[[CLLocationManager alloc] init]; self.gps.delegate=self;
      self.gps.desiredAccuracy=kCLLocationAccuracyBestForNavigation;
      self.gps.distanceFilter=kCLDistanceFilterNone;
      self.gps.pausesLocationUpdatesAutomatically=NO;
      self.gps.activityType=CLActivityTypeOtherNavigation;
      self.ready=YES;result(nil);
    });
  });
}
- (void)requireLocation:(FlutterResult)result action:(void (^)(void))action
{
  CLAuthorizationStatus status=self.gps.authorizationStatus;
  if(status==kCLAuthorizationStatusNotDetermined) {[self.gps requestWhenInUseAuthorization];result([FlutterError errorWithCode:@"LOCATION_PERMISSION" message:@"اسمح بالموقع ثم حاول مرة أخرى" details:nil]);return;}
  if(status!=kCLAuthorizationStatusAuthorizedAlways && status!=kCLAuthorizationStatusAuthorizedWhenInUse) {result([FlutterError errorWithCode:@"LOCATION_PERMISSION" message:@"اسمح بالوصول إلى الموقع من إعدادات الهاتف" details:nil]);return;}
  [self.gps startUpdatingLocation];[self.gps startUpdatingHeading]; action();result(nil);
}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result
{
  if([call.method isEqualToString:@"initialize"]) {[self initialize:result];return;}
  if(!self.ready) {result([FlutterError errorWithCode:@"NOT_READY" message:@"محرك الخرائط غير جاهز" details:nil]);return;}
  NSDictionary * args=call.arguments;auto & framework=MukshatFramework();
  if([call.method isEqualToString:@"search"])
  {
    NSString * query=args[@"query"];int64_t timestamp=[args[@"id"] longLongValue];self.queryId=timestamp;
    framework.GetSearchAPI().CancelAllSearches();
    search::EverywhereSearchParams params;
    params.m_query=query.UTF8String;params.m_inputLocale="ar";
    __weak MKOrganicPlugin * weakSelf=self;
    params.m_onResults=[weakSelf,timestamp](search::Results results) {
      MKOrganicPlugin * owner=weakSelf;if(!owner || owner.queryId!=timestamp)return;
      NSMutableArray * rows=[NSMutableArray array];
      for(auto const & item:results) if(item.GetResultType()==search::Result::Type::Feature || item.GetResultType()==search::Result::Type::LatLon) {
        auto const ll=mercator::ToLatLon(item.GetFeatureCenter());
        [rows addObject:@{@"name":@(item.GetString().c_str()),@"lat":@(ll.m_lat),@"lon":@(ll.m_lon)}];
      }
      [owner emit:@{@"type":@"search",@"id":@(timestamp),@"items":rows,@"done":@(results.IsEndMarker())}];
    };
    if(query.length) framework.GetSearchAPI().SearchEverywhere(std::move(params));
    else [self emit:@{@"type":@"search",@"id":@(timestamp),@"items":@[],@"done":@YES}];
  }
  else if([call.method isEqualToString:@"select"])
  {
    self.targetName=args[@"name"];self.targetLat=[args[@"lat"] doubleValue];self.targetLon=[args[@"lon"] doubleValue];
    framework.SetViewportCenter(mercator::FromLatLon(self.targetLat,self.targetLon),15);
  }
  else if([call.method isEqualToString:@"zoomIn"]) framework.Scale(Framework::SCALE_MAG,true);
  else if([call.method isEqualToString:@"zoomOut"]) framework.Scale(Framework::SCALE_MIN,true);
  else if([call.method isEqualToString:@"locate"]) {[self requireLocation:result action:^{MukshatFramework().SwitchMyPositionNextMode();}];return;}
  else if([call.method isEqualToString:@"navigate"])
  {
    if(!self.location) {result([FlutterError errorWithCode:@"GPS_PENDING" message:@"انتظر تحديد موقع GPS" details:nil]);return;}
    self.mode=args[@"mode"];self.targetName=args[@"name"];self.targetLat=[args[@"lat"] doubleValue];self.targetLon=[args[@"lon"] doubleValue];
    auto & routing=framework.GetRoutingManager();routing.CloseRouting(true);
    routing.SetRouter([self.mode isEqualToString:@"vehicle"]?routing::RouterType::Vehicle:routing::RouterType::Ruler);
    RouteMarkData start;start.m_isMyPosition=true;start.m_pointType=RouteMarkType::Start;start.m_position=mercator::FromLatLon(self.location.coordinate.latitude,self.location.coordinate.longitude);
    RouteMarkData end;end.m_pointType=RouteMarkType::Finish;end.m_title=self.targetName.UTF8String;end.m_position=mercator::FromLatLon(self.targetLat,self.targetLon);
    routing.AddRoutePoint(std::move(start),false);routing.AddRoutePoint(std::move(end),false);
    __weak MKOrganicPlugin * weakSelf=self;
    routing.SetRouteBuildingListener([weakSelf](routing::RouterResultCode code,storage::CountriesSet const & missing) {
      dispatch_async(dispatch_get_main_queue(),^{MKOrganicPlugin * owner=weakSelf;if(!owner)return;
        if(code==routing::RouterResultCode::NoError) {
          MukshatFramework().GetRoutingManager().FollowRoute();owner.navigating=YES;
          owner.gps.allowsBackgroundLocationUpdates=YES;UIApplication.sharedApplication.idleTimerDisabled=YES;
          [owner publishRoute];
        } else [owner emit:@{@"type":@"error",@"message":@"تعذر حساب المسار؛ تأكد من توفر خرائط المنطقة"}];
      });
    });
    routing.BuildRoute();
  }
  else if([call.method isEqualToString:@"stopNavigation"])
  {
    self.navigating=NO;framework.GetRoutingManager().CloseRouting(true);
    UIApplication.sharedApplication.idleTimerDisabled=NO;
    self.gps.allowsBackgroundLocationUpdates=self.recording;
  }
  else if([call.method isEqualToString:@"startRecording"])
  {
    [self requireLocation:result action:^{
      if(self.recording)return;
      self.journalPath=[[self tracksDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%.0f.active",NSDate.date.timeIntervalSince1970*1000]];
      [NSFileManager.defaultManager createFileAtPath:self.journalPath contents:NSData.data attributes:nil];
      self.trackPoints=0;self.trackDistance=0;self.previous=nil;
      MukshatFramework().StartTrackRecording();self.recording=YES;self.gps.allowsBackgroundLocationUpdates=YES;
    }];return;
  }
  else if([call.method isEqualToString:@"stopRecording"])
  {
    BOOL save=[args[@"save"] boolValue];
    if(self.recording) {
      if(save && !framework.IsTrackRecordingEmpty())framework.SaveTrackRecordingWithName("مسار مكشات");
      framework.StopTrackRecording();self.recording=NO;
      if(save && self.trackPoints) [NSFileManager.defaultManager moveItemAtPath:self.journalPath toPath:[[self.journalPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"jsonl"] error:nil];
      else [NSFileManager.defaultManager removeItemAtPath:self.journalPath error:nil];
      self.gps.allowsBackgroundLocationUpdates=self.navigating;
    }
  }
  else if([call.method isEqualToString:@"tracks"])
  {
    NSMutableArray * rows=[NSMutableArray array];
    for(NSString * file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:[self tracksDirectory] error:nil])
      if([@[@"active",@"jsonl"] containsObject:file.pathExtension]) {
        NSString * text=[NSString stringWithContentsOfFile:[[self tracksDirectory] stringByAppendingPathComponent:file] encoding:NSUTF8StringEncoding error:nil];
        NSUInteger count=0;for(NSString * line in [text componentsSeparatedByString:@"\n"])if(line.length)count++;
        [rows addObject:@{@"id":file,@"name":[@"مسار " stringByAppendingString:file.stringByDeletingPathExtension],@"points":@(count)}];
      }
    result(rows);return;
  }
  else if([call.method isEqualToString:@"showTrack"])
  {
    NSString * name=args[@"id"];
    if(![name isEqualToString:name.lastPathComponent]) {result([FlutterError errorWithCode:@"TRACK" message:@"مسار غير صالح" details:nil]);return;}
    NSString * text=[NSString stringWithContentsOfFile:[[self tracksDirectory] stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:nil];
    NSMutableString * coords=[NSMutableString string];double lat=0,lon=0;
    for(NSString * line in [text componentsSeparatedByString:@"\n"])if(line.length) {
      NSDictionary * point=[NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
      lat=[point[@"lat"] doubleValue];lon=[point[@"lon"] doubleValue];[coords appendFormat:@"%f,%f,0 ",lon,lat];
    }
    NSString * kml=[NSString stringWithFormat:@"<?xml version=\"1.0\"?><kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document><name>مسار مكشات</name><Placemark><LineString><coordinates>%@</coordinates></LineString></Placemark></Document></kml>",coords];
    NSString * path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"prototype-preview.kml"];
    [kml writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    framework.GetBookmarkManager().LoadBookmark(path.UTF8String,true);
    framework.SetViewportCenter(mercator::FromLatLon(lat,lon),15);
  }
  else if([call.method isEqualToString:@"share"])
  {
    NSString * link=[NSString stringWithFormat:@"https://mukshatapp.github.io/map/?ll=%.6f,%.6f",self.targetLat,self.targetLon];
    UIActivityViewController * share=[[UIActivityViewController alloc] initWithActivityItems:@[link] applicationActivities:nil];
    UIWindowScene * scene=(UIWindowScene *)UIApplication.sharedApplication.connectedScenes.allObjects.firstObject;
    UIViewController * top=scene.windows.firstObject.rootViewController;
    [top presentViewController:share animated:YES completion:nil];
  }
  else if([call.method isEqualToString:@"attribution"])
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://organicmaps.app/copyright/"] options:@{} completionHandler:nil];
  else {result(FlutterMethodNotImplemented);return;}
  result(nil);
}
- (void)publishRoute
{
  if(!self.location)return;
  double latitude=self.location.coordinate.latitude*M_PI/180, target=self.targetLat*M_PI/180;
  double delta=(self.targetLon-self.location.coordinate.longitude)*M_PI/180;
  double bearing=atan2(sin(delta)*cos(target),cos(latitude)*sin(target)-sin(latitude)*cos(target)*cos(delta))*180/M_PI;
  CLLocation * destination=[[CLLocation alloc] initWithLatitude:self.targetLat longitude:self.targetLon];
  double distance=[self.location distanceFromLocation:destination];
  if([self.mode isEqualToString:@"vehicle"]) {
    routing::FollowingInfo info;MukshatFramework().GetRoutingManager().GetRouteFollowingInfo(info);
    distance=info.m_distToTarget.To(platform::Distance::Units::Meters).GetDistance();
  }
  [self emit:@{@"type":@"route",@"active":@(self.navigating),@"distance":@(distance),@"bearing":@(bearing),@"message":@"ملاحة دون اتصال"}];
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
  for(CLLocation * fix in locations) {
    if(fix.horizontalAccuracy<0 || fix.horizontalAccuracy>100)continue;
    self.location=fix;
    location::GpsInfo info;info.m_source=location::EAppleNative;info.m_timestamp=fix.timestamp.timeIntervalSince1970;
    info.m_latitude=fix.coordinate.latitude;info.m_longitude=fix.coordinate.longitude;info.m_horizontalAccuracy=fix.horizontalAccuracy;
    info.m_altitude=fix.altitude;info.m_verticalAccuracy=fix.verticalAccuracy;info.m_speed=fix.speed;info.m_bearing=fix.course;
    GpsTracker::Instance().OnLocationUpdated(info);MukshatFramework().OnLocationUpdate(info);
    [self emit:@{@"type":@"location",@"name":@"موقعي",@"lat":@(fix.coordinate.latitude),@"lon":@(fix.coordinate.longitude),@"speed":@(MAX(0,fix.speed*3.6))}];
    if(self.recording) {
      NSDictionary * point=@{@"lat":@(fix.coordinate.latitude),@"lon":@(fix.coordinate.longitude),@"time":@(fix.timestamp.timeIntervalSince1970*1000),@"altitude":@(fix.altitude),@"accuracy":@(fix.horizontalAccuracy)};
      NSData * data=[NSJSONSerialization dataWithJSONObject:point options:0 error:nil];
      NSFileHandle * file=[NSFileHandle fileHandleForWritingAtPath:self.journalPath];
      [file seekToEndOfFile];[file writeData:data];[file writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];[file synchronizeFile];[file closeFile];
      if(self.previous)self.trackDistance+=[fix distanceFromLocation:self.previous];self.previous=fix;self.trackPoints++;
      [self emit:@{@"type":@"recording",@"active":@YES,@"distance":@(self.trackDistance),@"points":@(self.trackPoints)}];
    }
    if(self.navigating)[self publishRoute];
  }
}
- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)heading
{
  if(heading.headingAccuracy<0)return;
  double north=heading.trueHeading>=0?heading.trueHeading:heading.magneticHeading;
  location::CompassInfo compass;compass.m_bearing=north*M_PI/180;MukshatFramework().OnCompassUpdate(compass);
  [self emit:@{@"type":@"heading",@"heading":@(north)}];
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
  [self emit:@{@"type":@"error",@"message":error.localizedDescription}];
}
@end
