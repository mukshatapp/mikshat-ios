package com.mikshat.prototype;

import android.Manifest;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.view.WindowManager;
import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import app.organicmaps.sdk.Framework;
import app.organicmaps.sdk.MapController;
import app.organicmaps.sdk.MapRenderingListener;
import app.organicmaps.sdk.MapView;
import app.organicmaps.sdk.location.LocationState;
import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.*;
import io.flutter.plugin.platform.*;
import java.util.Map;

public final class MainActivity extends FlutterFragmentActivity {
  MapRuntime runtime;
  MethodChannel.Result permissionResult;
  Runnable afterPermission;
  @Override public void configureFlutterEngine(@NonNull FlutterEngine engine) {
    super.configureFlutterEngine(engine);
    runtime=MapRuntime.get(this);
    new EventChannel(engine.getDartExecutor().getBinaryMessenger(),"com.mikshat.prototype/events")
      .setStreamHandler(new EventChannel.StreamHandler() {
        public void onListen(Object args,EventChannel.EventSink events) {runtime.sink=events;}
        public void onCancel(Object args) {runtime.sink=null;}
      });
    new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"com.mikshat.prototype/engine")
      .setMethodCallHandler(this::call);
    engine.getPlatformViewsController().getRegistry().registerViewFactory("com.mikshat.prototype/map",
      new PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        @Override public PlatformView create(Context context,int id,Object args) {return new NativeMap();}
      });
  }
  private void call(MethodCall call,MethodChannel.Result result) {
    try {
      if(call.method.equals("initialize")) {runtime.initialize(result);return;}
      if(!runtime.ready) {result.error("NOT_READY","محرك الخرائط غير جاهز",null);return;}
      switch(call.method) {
        case "search":runtime.search(call.argument("query"),((Number)call.argument("id")).longValue());break;
        case "select":runtime.select(call.argument("name"),number(call,"lat"),number(call,"lon"),true);break;
        case "zoomIn":app.organicmaps.sdk.Map.zoomIn();break;
        case "zoomOut":app.organicmaps.sdk.Map.zoomOut();break;
        case "locate":
          withLocation(result,()-> {runtime.sdk.getLocationHelper().start();LocationState.nativeSwitchToNextMode();});return;
        case "navigate":
          withLocation(result,()-> {
            runtime.select(call.argument("name"),number(call,"lat"),number(call,"lon"),false);
            runtime.navigate(call.argument("mode"));
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
          });return;
        case "stopNavigation":runtime.stopNavigation();getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);break;
        case "startRecording":withLocation(result,()-> {try{runtime.startRecording();}catch(Exception e){throw new RuntimeException(e);}});return;
        case "stopRecording":runtime.stopRecording(Boolean.TRUE.equals(call.argument("save")));break;
        case "tracks":result.success(runtime.tracks());return;
        case "showTrack":runtime.showTrack(call.argument("id"));break;
        case "share":
          Intent share=new Intent(Intent.ACTION_SEND);share.setType("text/plain");
          share.putExtra(Intent.EXTRA_TEXT,runtime.targetName+"\nhttps://mukshatapp.github.io/map/?ll="+runtime.targetLat+","+runtime.targetLon);
          startActivity(Intent.createChooser(share,"مشاركة الموقع"));break;
        case "attribution":startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse("https://organicmaps.app/copyright/")));break;
        default:result.notImplemented();return;
      }
      result.success(null);
    } catch(Throwable e) {result.error("ENGINE",e.getMessage(),null);}
  }
  private static double number(MethodCall call,String key) {return ((Number)call.argument(key)).doubleValue();}
  private void withLocation(MethodChannel.Result result,Runnable action) {
    if(ContextCompat.checkSelfPermission(this,Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED) {
      try{action.run();result.success(null);}catch(Exception e){result.error("LOCATION",e.getMessage(),null);}return;
    }
    if(permissionResult!=null) {result.error("PERMISSION_PENDING","يوجد طلب إذن موقع قيد الانتظار",null);return;}
    permissionResult=result;afterPermission=action;
    ActivityCompat.requestPermissions(this,new String[]{Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION},101);
  }
  @Override public void onRequestPermissionsResult(int request,@NonNull String[] permissions,@NonNull int[] grants) {
    super.onRequestPermissionsResult(request,permissions,grants);
    if(request!=101 || permissionResult==null)return;
    MethodChannel.Result result=permissionResult;Runnable action=afterPermission;permissionResult=null;afterPermission=null;
    if(ContextCompat.checkSelfPermission(this,Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED) {
      try{action.run();result.success(null);}catch(Exception e){result.error("LOCATION",e.getMessage(),null);}
    } else result.error("LOCATION_PERMISSION","يلزم السماح بالموقع الدقيق لتسجيل المسار والملاحة",null);
  }
  final class NativeMap implements PlatformView,MapRenderingListener {
    final MapView view;
    final MapController controller;
    NativeMap() {
      view=new MapView(MainActivity.this,null);
      controller=new MapController(view,runtime.sdk.getLocationHelper(),this,
        ()->runtime.emit("error","message","محرك الرسوم غير مدعوم على هذا الجهاز"),false);
      getLifecycle().addObserver(controller);
    }
    @Override public View getView(){return view;}
    @Override public void dispose(){getLifecycle().removeObserver(controller);controller.onDestroy(MainActivity.this);}
    @Override public void onRenderingInitializationFinished() {
      Framework.nativeSetViewportCenter(24.7136,46.6753,12);
      controller.updateBottomWidgetsOffset(0,(int)(145*getResources().getDisplayMetrics().density));
      if(ContextCompat.checkSelfPermission(MainActivity.this,Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED)
        runtime.sdk.getLocationHelper().start();
    }
  }
}
