// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.PixelFormat;
import android.media.tv.TvContract;
import android.os.Build;
import android.os.IBinder;
import android.view.WindowManager;

/**
 * Overlay modu: HDMI'yı TV'nin kendi giriş ekranı gösterir, altyazı onun üstündeki şeffaf bir pencerede durur.
 * Bazı TV'lerde (TCL, MediaTek) uygulama içindeki TvView'de görüntü siyah kalıyor, ses geliyor; HDMI'yı TV'nin
 * kendi ekranı çizdiğinde bu sorun olmaz. "Diğer uygulamaların üzerinde göster" izni gerekir.
 * Pencere odak almaz: kumanda TV'de normal çalışır, CouchSubs'ın kumanda tuşları bu modda kullanılmaz.
 */
public class OverlayService extends Service implements TvPage.Host {
    static final String EXTRA_PARAMS = "params";
    private static final String CHANNEL = "overlay";
    private static final int NOTIFICATION_ID = 1;

    /** Servis çalışıyor mu; MainActivity yeniden açıldığında altyazıyı kapatmak için bakar. */
    static volatile boolean running;

    private WindowManager windows;
    private TvPage page;
    /** Sayfanın son istediği giriş ve TV'nin en son geçirildiği giriş (0: henüz geçilmedi). */
    private int lastPort;
    private int tunedPort;

    static void start(Context context, String params) {
        Intent intent = new Intent(context, OverlayService.class).putExtra(EXTRA_PARAMS, params);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent);
        else context.startService(intent);
    }

    static void stop(Context context) {
        context.stopService(new Intent(context, OverlayService.class));
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        goForeground();
        String params = intent == null ? null : intent.getStringExtra(EXTRA_PARAMS);
        if (params == null) params = "";
        if (page == null) {
            running = true;
            showOverlay(params);
        } else {
            // CouchSubs yeniden başlatıldı: TV başka bir uygulamaya geçmiş olabilir, HDMI'ya yeniden geçilir.
            page.relaunch(params);
            tunedPort = 0;
            if (lastPort > 0) showHdmi(lastPort);
        }
        return START_NOT_STICKY;
    }

    private void showOverlay(String params) {
        windows = (WindowManager) getSystemService(WINDOW_SERVICE);
        page = new TvPage(this, this, params);
        int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;
        WindowManager.LayoutParams layout = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                        | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                PixelFormat.TRANSLUCENT);
        windows.addView(page.webView, layout);
        page.load();
    }

    /** TV'yi kendi HDMI giriş ekranına geçirir; altyazı penceresi üstte kalır. */
    @Override
    public void showHdmi(int port) {
        if (page == null) return;
        lastPort = port;
        if (port == tunedPort) {
            page.status("ready");
            return;
        }
        String id = TvPage.hdmiInputId(this, port);
        if (id == null) {
            page.status("sourceError");
            return;
        }
        Intent view = new Intent(Intent.ACTION_VIEW, TvContract.buildChannelUriForPassthroughInput(id))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(view);
            tunedPort = port;
            page.status("ready");
        } catch (ActivityNotFoundException | SecurityException e) {
            // TV bu yolla girişe geçemiyor: kullanıcı girişi kumandadan seçer, altyazı yine üstte görünür.
            page.status("sourceError");
        }
    }

    @Override
    public void exit() { stopSelf(); }

    private void goForeground() {
        NotificationManager notifications = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.createNotificationChannel(
                    new NotificationChannel(CHANNEL, "CouchSubs", NotificationManager.IMPORTANCE_LOW));
            builder = new Notification.Builder(this, CHANNEL);
        } else {
            builder = new Notification.Builder(this);
        }
        Notification notification = builder
                .setSmallIcon(R.mipmap.icon)
                .setContentTitle("CouchSubs")
                .setContentText(Texts.overlayRunning())
                .setOngoing(true)
                .build();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    @Override
    public void onDestroy() {
        running = false;
        if (page != null) {
            windows.removeView(page.webView);
            page.destroy();
            page = null;
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }
}
