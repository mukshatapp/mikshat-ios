package com.mikshat.prototype;

import static org.junit.Assert.*;
import android.Manifest;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.location.Criteria;
import android.location.Location;
import android.location.LocationManager;
import android.os.SystemClock;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileInputStream;
import java.lang.reflect.Field;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Real native engine with test-only OS GPS fixes on an emulator; no mock search or routing. */
@RunWith(AndroidJUnit4.class)
public class OfflineEngineTest {
  private final Instrumentation test=InstrumentationRegistry.getInstrumentation();
  private final Context context=test.getTargetContext();
  private final MapRuntime runtime=MapRuntime.get(context);
  private void ui(Runnable action){test.runOnMainSync(action);}
  private void waitFor(java.util.function.BooleanSupplier condition,String message,long millis) throws Exception {
    long end=SystemClock.uptimeMillis()+millis;
    while(SystemClock.uptimeMillis()<end){
      AtomicBoolean result=new AtomicBoolean();
      ui(()->result.set(condition.getAsBoolean()));
      if(result.get())return;
      Thread.sleep(250);
    }
    fail(message);
  }
  private void shell(String command) throws Exception {
    try(android.os.ParcelFileDescriptor descriptor=test.getUiAutomation().executeShellCommand(command);
        FileInputStream input=new FileInputStream(descriptor.getFileDescriptor())) {
      input.transferTo(java.io.OutputStream.nullOutputStream());
    }
  }
  private void fix(LocationManager manager,double latitude,double longitude) throws Exception {
    Location location=new Location(LocationManager.GPS_PROVIDER);
    location.setLatitude(latitude);location.setLongitude(longitude);
    location.setAccuracy(5);location.setAltitude(600);
    location.setSpeed(3);location.setBearing(20);
    location.setTime(System.currentTimeMillis());
    location.setElapsedRealtimeNanos(SystemClock.elapsedRealtimeNanos());
    manager.setTestProviderLocation(LocationManager.GPS_PROVIDER,location);
    Thread.sleep(1500);
  }
  @Test public void offlineMapSearchRoutesAndLockedRecording() throws Exception {
    Intent open=new Intent(context,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    test.startActivitySync(open);
    waitFor(()->runtime.ready && app.organicmaps.sdk.Map.isEngineCreated(),"Native map renderer did not initialize",120000);
    assertTrue(new File(context.getFilesDir(),"260714/Saudi Arabia_North.mwm").isFile());
    assertTrue(new File(context.getFilesDir(),"260714/Saudi Arabia_South.mwm").isFile());
    shell("svc wifi disable");shell("svc data disable");

    ui(()->runtime.search("الرياض",91));
    Field results=MapRuntime.class.getDeclaredField("cachedResults");results.setAccessible(true);
    waitFor(()->{
      try{return !((List<?>)results.get(runtime)).isEmpty();}catch(IllegalAccessException e){return false;}
    },"Offline Arabic search returned no results",60000);

    LocationManager manager=(LocationManager)context.getSystemService(Context.LOCATION_SERVICE);
    manager.addTestProvider(LocationManager.GPS_PROVIDER,false,false,false,false,true,true,true,
      Criteria.POWER_LOW,Criteria.ACCURACY_FINE);
    manager.setTestProviderEnabled(LocationManager.GPS_PROVIDER,true);
    ui(()->runtime.sdk.getLocationHelper().start());
    fix(manager,24.7136,46.6753);
    waitFor(()->runtime.location!=null,"Native GPS did not receive emulator fix",15000);

    ui(()->{
      runtime.select("اختبار الملاحة",24.7165,46.6758,false);
      runtime.navigate("vehicle");
    });
    waitFor(()->runtime.navigating,"Offline vehicle route did not build",60000);
    ui(runtime::stopNavigation);
    ui(()->runtime.navigate("direct"));
    waitFor(()->runtime.navigating,"Offline direct route did not build",30000);
    ui(runtime::stopNavigation);

    ui(()->{try{runtime.startRecording();}catch(Exception e){throw new RuntimeException(e);}});
    fix(manager,24.7137,46.6754);
    int before=runtime.points;
    shell("input keyevent KEYCODE_SLEEP");
    for(int i=0;i<5;i++)fix(manager,24.7138+i*.0001,46.6755+i*.0001);
    int after=runtime.points;
    shell("input keyevent KEYCODE_WAKEUP");shell("wm dismiss-keyguard");
    assertTrue("No new native GPS points were written while locked",after>before);
    ui(()->{try{runtime.stopRecording(true);}catch(Exception e){throw new RuntimeException(e);}});
    assertFalse(runtime.recording);
    assertTrue(new File(context.getFilesDir(),"prototype-tracks").listFiles((dir,name)->name.endsWith(".jsonl")).length>0);
    Thread.sleep(2000);
    Bitmap image=test.getUiAutomation().takeScreenshot();
    assertNotNull("No compositor screenshot",image);
    try(FileOutputStream output=new FileOutputStream(new File(context.getFilesDir(),"prototype-map-proof.png"))){
      image.compress(Bitmap.CompressFormat.PNG,100,output);
    }
    manager.removeTestProvider(LocationManager.GPS_PROVIDER);
  }
}
