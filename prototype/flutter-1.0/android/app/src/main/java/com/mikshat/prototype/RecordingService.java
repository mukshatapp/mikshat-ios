package com.mikshat.prototype;

import android.app.*;
import android.content.Intent;
import android.os.IBinder;
import android.content.pm.ServiceInfo;
import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;

/** Location foreground service keeps native GPS alive when the display is locked. */
public final class RecordingService extends Service {
  @Override public void onCreate() {
    super.onCreate();
    NotificationManager manager=getSystemService(NotificationManager.class);
    manager.createNotificationChannel(new NotificationChannel("mukshat-track","الملاحة وتسجيل المسار",NotificationManager.IMPORTANCE_LOW));
  }
  @Override public int onStartCommand(Intent intent,int flags,int startId) {
    MapRuntime runtime=MapRuntime.get(this);
    if(!runtime.ready || !(runtime.recording||runtime.navigating)) {stopSelf();return START_NOT_STICKY;}
    Intent open=new Intent(this,MainActivity.class);
    PendingIntent pending=PendingIntent.getActivity(this,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
    Notification notification=new NotificationCompat.Builder(this,"mukshat-track")
      .setSmallIcon(android.R.drawable.ic_menu_mylocation).setContentTitle("مكشات 1.0")
      .setContentText(runtime.recording?"تسجيل المسار مستمر عند قفل الشاشة":"الملاحة تعمل")
      .setOngoing(true).setContentIntent(pending).build();
    ServiceCompat.startForeground(this,1001,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
    runtime.sdk.getLocationHelper().start();
    return START_NOT_STICKY;
  }
  @Override public IBinder onBind(Intent intent) {return null;}
}
