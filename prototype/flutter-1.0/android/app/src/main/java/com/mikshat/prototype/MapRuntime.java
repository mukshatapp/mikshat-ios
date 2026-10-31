package com.mikshat.prototype;

import android.content.Context;
import android.content.Intent;
import android.location.Location;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import app.organicmaps.sdk.Framework;
import app.organicmaps.sdk.OrganicMaps;
import app.organicmaps.sdk.Router;
import app.organicmaps.sdk.bookmarks.data.MapObject;
import app.organicmaps.sdk.location.LocationListener;
import app.organicmaps.sdk.location.TrackRecorder;
import app.organicmaps.sdk.routing.RoutingController;
import app.organicmaps.sdk.routing.RoutingInfo;
import app.organicmaps.sdk.search.SearchEngine;
import app.organicmaps.sdk.search.SearchListener;
import app.organicmaps.sdk.search.SearchResult;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.Executors;
import org.json.JSONObject;

/** Process lifetime engine: surface disposal must not stop a recording. */
public final class MapRuntime implements LocationListener, SearchListener, RoutingController.Container {
  private static MapRuntime instance;
  public static synchronized MapRuntime get(Context context) {
    if (instance == null) instance = new MapRuntime(context.getApplicationContext());
    return instance;
  }
  final Context context;
  OrganicMaps sdk;
  boolean ready, initializing, recording, navigating;
  String navigationMode = "direct";
  EventChannel.EventSink sink;
  final Handler main = new Handler(Looper.getMainLooper());
  final List<MethodChannel.Result> waiters = new ArrayList<>();
  Location location, previousTrackPoint;
  double targetLat, targetLon, heading, trackLength;
  String targetName = "نقطة الخريطة";
  long searchId, lastDirectBuild;
  int points;
  File journal;

  private MapRuntime(Context context) { this.context = context; }
  void emit(String type, Object... pairs) {
    java.util.Map<String,Object> event = new HashMap<>(); event.put("type", type);
    for (int i=0;i<pairs.length;i+=2) event.put((String)pairs[i],pairs[i+1]);
    main.post(() -> { if (sink != null) sink.success(event); });
  }
  void initialize(MethodChannel.Result result) {
    if (ready) { result.success(null); return; }
    waiters.add(result);
    if (initializing) return;
    initializing = true;
    Executors.newSingleThreadExecutor().execute(() -> {
      try {
        File maps = new File(context.getFilesDir(), "maps/260714");
        if (!maps.exists() && !maps.mkdirs()) throw new IOException("Cannot create map directory");
        install(maps, "Saudi Arabia_North.mwm", 71760131L,
          "6cd35fcb5b2bcd8c0ce5f9249426126c1a3c56635033c07fde855b9316651fe0");
        install(maps, "Saudi Arabia_South.mwm", 69904708L,
          "7591a4c97628994b04856b84988ea6259bda4bf4c194702ef39817f02d484425");
        // Set before constructing the SDK so it registers the installed country files on first load.
        File settings = new File(context.getFilesDir(), "settings.ini");
        if (!settings.exists()) try (FileOutputStream out = new FileOutputStream(settings)) {
          out.write(("StoragePath=" + new File(context.getFilesDir(), "maps").getAbsolutePath() + "/\nMapLanguageCode=ar\nMapStyle=MapStyleOutdoorsLight\n").getBytes(StandardCharsets.UTF_8));
        }
        main.post(() -> {
          try {
            Locale.setDefault(Locale.forLanguageTag("ar"));
            sdk = new OrganicMaps(context,"prototype","com.mikshat.prototype",1,"1.0.0");
            sdk.init(() -> {});
            app.organicmaps.sdk.util.Config.setTransliteration(false);
            sdk.getLocationHelper().addListener(this);
            sdk.getSensorHelper().addListener(north -> {
              heading = Math.toDegrees(north);
              app.organicmaps.sdk.Map.onCompassUpdated(north,false);
              emit("heading","heading",heading);
            });
            SearchEngine.INSTANCE.addListener(this);
            RoutingController.get().attach(this);
            Framework.nativePlacePageActivationListener(new app.organicmaps.sdk.PlacePageActivationListener() {
              public void onPlacePageActivated(app.organicmaps.sdk.widget.placepage.PlacePageData data) {
                if (data instanceof MapObject point) select(point.getTitle(),point.getLat(),point.getLon(),false);
              }
              public void onPlacePageDeactivated() {}
            });
            ready = true; initializing = false;
            for (MethodChannel.Result waiter : waiters) waiter.success(null);
            waiters.clear();
          } catch (Throwable e) { failInitialization(e); }
        });
      } catch (Throwable e) { main.post(() -> failInitialization(e)); }
    });
  }
  private void install(File directory,String name,long size,String expected) throws Exception {
    File file=new File(directory,name);
    if(file.isFile() && file.length()==size) return;
    emit("status","message","تجهيز " + (name.contains("North") ? "خريطة الشمال" : "خريطة الجنوب"));
    File part=new File(directory,name+".part");
    MessageDigest digest=MessageDigest.getInstance("SHA-256");
    try(InputStream in=context.getAssets().open("regions/"+name);FileOutputStream out=new FileOutputStream(part)) {
      byte[] buffer=new byte[1024*1024];int n;
      while((n=in.read(buffer))!=-1) { out.write(buffer,0,n);digest.update(buffer,0,n); }
      out.getFD().sync();
    }
    StringBuilder hash=new StringBuilder();for(byte b:digest.digest()) hash.append(String.format(Locale.ROOT,"%02x",b));
    if(part.length()!=size || !hash.toString().equals(expected)) throw new IOException("Map integrity check failed: "+name);
    if(!part.renameTo(file)) throw new IOException("Cannot install map: "+name);
  }
  private void failInitialization(Throwable e) {
    initializing=false;
    for(MethodChannel.Result waiter:waiters) waiter.error("ENGINE_INIT",e.toString(),null);
    waiters.clear();
  }
  void search(String query,long id) {
    searchId=id;
    if(query.isEmpty()) { SearchEngine.INSTANCE.cancel(); emit("search","id",id,"items",List.of(),"done",true);return; }
    if(!SearchEngine.INSTANCE.searchInteractive(query,false,"ar",id,true,location!=null,
      location==null?0:location.getLatitude(),location==null?0:location.getLongitude()))
      emit("search","id",id,"items",List.of(),"done",true);
  }
  private List<java.util.Map<String,Object>> cachedResults=List.of();
  @Override public void onResultsUpdate(SearchResult[] results,long timestamp) {
    if(timestamp!=searchId) return;
    List<java.util.Map<String,Object>> rows=new ArrayList<>();
    for(SearchResult r:results) if(r.type==SearchResult.TYPE_RESULT) rows.add(java.util.Map.of(
      "name",r.getTitle(context),"lat",r.lat,"lon",r.lon));
    cachedResults=rows;emit("search","id",timestamp,"items",rows,"done",false);
  }
  @Override public void onResultsEnd(long timestamp) {
    if(timestamp==searchId) emit("search","id",timestamp,"items",cachedResults,"done",true);
  }
  void select(String name,double lat,double lon,boolean move) {
    targetName=name;targetLat=lat;targetLon=lon;
    if(move) Framework.nativeSetViewportCenter(lat,lon,15);
    emit("selection","name",name,"lat",lat,"lon",lon);
  }
  void navigate(String mode) {
    if(location==null) throw new IllegalStateException("انتظر تحديد موقع GPS قبل بدء الملاحة");
    navigationMode=mode;
    buildRoute();
  }
  private void buildRoute() {
    MapObject start=MapObject.createMapObject(MapObject.MY_POSITION,"موقعي","",location.getLatitude(),location.getLongitude());
    MapObject end=MapObject.createMapObject(MapObject.API_POINT,targetName,"",targetLat,targetLon);
    RoutingController.get().prepare(start,end,navigationMode.equals("vehicle")?Router.Vehicle:Router.Ruler);
    emit("route","message","جارٍ حساب المسار دون اتصال");
  }
  @Override public void showRoutePlan(boolean show,Runnable completion) { if(completion!=null) completion.run(); }
  @Override public void onBuiltRoute() {
    if(!navigating) { navigating=true;RoutingController.get().start();updateService(); }
    publishRoute();
  }
  @Override public void onCommonBuildError(int code,String[] missing) {
    emit("error","message",missing!=null && missing.length>0 ? "المسار يحتاج خرائط إضافية: "+String.join(", ",missing) : "تعذر حساب المسار ("+code+")");
  }
  void stopNavigation() {
    navigating=false;RoutingController.get().cancel();updateService();
  }
  private void publishRoute() {
    if(location==null) return;
    float[] values=new float[3];Location.distanceBetween(location.getLatitude(),location.getLongitude(),targetLat,targetLon,values);
    RoutingInfo info=Framework.nativeGetRouteFollowingInfo();
    double distance=navigationMode.equals("vehicle") && info!=null?info.distToTarget.mDistance:values[0];
    emit("route","active",navigating,"distance",distance,"bearing",(double)values[1],"message",
      navigationMode.equals("vehicle")?"ملاحة بالسيارة دون اتصال":"توجيه "+(navigationMode.equals("compass")?"بالبوصلة":"مباشر"));
  }
  @Override public void onLocationUpdated(Location fix) {
    location=new Location(fix);
    emit("location","name","موقعي","lat",fix.getLatitude(),"lon",fix.getLongitude(),"speed",Math.max(0,fix.getSpeed()*3.6));
    if(recording) appendPoint(fix);
    if(navigating) publishRoute();
  }
  void startRecording() throws IOException {
    if(recording) return;
    File dir=new File(context.getFilesDir(),"prototype-tracks"); if(!dir.exists()&&!dir.mkdirs()) throw new IOException("Cannot create tracks directory");
    journal=new File(dir,System.currentTimeMillis()+".active");
    if(!journal.createNewFile()) throw new IOException("Cannot create track journal");
    points=0;trackLength=0;previousTrackPoint=null;
    TrackRecorder.nativeStartTrackRecording();recording=true;updateService();emitRecording();
  }
  private void appendPoint(Location fix) {
    try {
      JSONObject json=new JSONObject();json.put("lat",fix.getLatitude());json.put("lon",fix.getLongitude());
      json.put("time",fix.getTime());json.put("altitude",fix.getAltitude());json.put("accuracy",fix.getAccuracy());
      try(FileOutputStream out=new FileOutputStream(journal,true)) {
        out.write((json+"\n").getBytes(StandardCharsets.UTF_8));out.getFD().sync();
      }
      if(previousTrackPoint!=null) trackLength+=fix.distanceTo(previousTrackPoint);
      previousTrackPoint=new Location(fix);points++;emitRecording();
    } catch(Exception e) { emit("error","message","تعذر حفظ نقطة المسار: "+e.getMessage()); }
  }
  private void emitRecording() {emit("recording","active",recording,"distance",trackLength,"points",points);}
  void stopRecording(boolean save) throws IOException {
    if(!recording) return;
    if(save && !TrackRecorder.nativeIsTrackRecordingEmpty()) TrackRecorder.nativeSaveTrackRecordingWithName("مسار مكشات "+new Date());
    TrackRecorder.nativeStopTrackRecording();recording=false;
    if(save && points>0) {
      File saved=new File(journal.getParentFile(),journal.getName().replace(".active",".jsonl"));
      if(!journal.renameTo(saved)) throw new IOException("Cannot finalize track");
    } else if(journal.exists()&&!journal.delete()) throw new IOException("Cannot discard track");
    updateService();emitRecording();
  }
  List<java.util.Map<String,Object>> tracks() throws IOException {
    List<java.util.Map<String,Object>> rows=new ArrayList<>();
    File dir=new File(context.getFilesDir(),"prototype-tracks");File[] files=dir.listFiles();if(files==null)return rows;
    Arrays.sort(files,Comparator.comparing(File::getName).reversed());
    for(File f:files) if(f.getName().endsWith(".jsonl")||f.getName().endsWith(".active")) {
      int count=0;try(BufferedReader reader=new BufferedReader(new FileReader(f))) {while(reader.readLine()!=null)count++;}
      rows.add(java.util.Map.of("id",f.getName(),"name",(f.getName().endsWith(".active")?"مسار غير مكتمل ":"مسار ")+f.getName().split("\\.")[0],"points",count));
    }
    return rows;
  }
  void showTrack(String id) throws Exception {
    if(!id.matches("[0-9]+\\.(jsonl|active)")) throw new IllegalArgumentException("Invalid track ID");
    File file=new File(new File(context.getFilesDir(),"prototype-tracks"),id);
    StringBuilder coordinates=new StringBuilder();double lat=0,lon=0;int count=0;
    try(BufferedReader reader=new BufferedReader(new FileReader(file))) {
      String line;while((line=reader.readLine())!=null) {JSONObject p=new JSONObject(line);lat=p.getDouble("lat");lon=p.getDouble("lon");coordinates.append(lon).append(',').append(lat).append(',').append(p.optDouble("altitude")).append(' ');count++;}
    }
    if(count==0)throw new IOException("المسار فارغ");
    File kml=new File(context.getCacheDir(),"preview-"+id+".kml");
    try(FileOutputStream out=new FileOutputStream(kml)) {out.write(("<?xml version=\"1.0\"?><kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document><name>عرض المسار</name><Placemark><name>مسار مكشات</name><LineString><coordinates>"+coordinates+"</coordinates></LineString></Placemark></Document></kml>").getBytes(StandardCharsets.UTF_8));}
    app.organicmaps.sdk.bookmarks.data.BookmarkManager.INSTANCE.loadBookmarksFile(kml.getAbsolutePath(),true);
    Framework.nativeSetViewportCenter(lat,lon,15);
  }
  void updateService() {
    Intent intent=new Intent(context,RecordingService.class);
    if(recording||navigating) androidx.core.content.ContextCompat.startForegroundService(context,intent);
    else context.stopService(intent);
  }
}
