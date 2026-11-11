// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Color;
import android.media.tv.TvContract;
import android.media.tv.TvView;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.KeyEvent;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.Toast;

/**
 * İki modda çalışır:
 * - Uygulama içi (varsayılan): HDMI girişini TvView ile tam ekran gösterir; üstünde şeffaf WebView'de LG ve Samsung'la
 *   ortak arayüz çalışır.
 * - Overlay (TCL ve elle seçilenler): HDMI'yı TV'nin kendi giriş ekranı gösterir, altyazıyı OverlayService üstte
 *   çizer. Bu ekran yalnız izni sorar, servisi başlatır ve kapanır; servis çalışırken yeniden açılırsa altyazıyı kapatır.
 */
public class MainActivity extends Activity implements TvPage.Host {
    private static final int OVERLAY_PERMISSION_REQUEST = 1;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private TvView tvView;
    private TvPage page;
    private String launchParams = "";
    /** Son açılan HDMI girişi; uygulama öne gelince ya da bağlantı kopunca yeniden açılır. */
    private String tunedInput;
    private int retuneAttempts;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        launchParams = paramsOf(getIntent());
        OverlayMode.remember(this, getIntent());

        if (OverlayMode.wanted(this)) {
            if (OverlayService.running) {
                OverlayService.stop(this);
                Toast.makeText(this, Texts.overlayStopped(), Toast.LENGTH_LONG).show();
                finish();
                return;
            }
            if (Settings.canDrawOverlays(this)) {
                startOverlay();
                return;
            }
            if (askOverlayPermission()) return;
            // İzin ekranı açılamadı: uygulama içi moda düşülür.
        }
        showInApp();
    }

    // --- Overlay modu ---

    private boolean askOverlayPermission() {
        Intent ask = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + getPackageName()));
        try {
            Toast.makeText(this, Texts.askPermission(), Toast.LENGTH_LONG).show();
            startActivityForResult(ask, OVERLAY_PERMISSION_REQUEST);
            return true;
        } catch (ActivityNotFoundException e) {
            return false;
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != OVERLAY_PERMISSION_REQUEST) return;
        // Bazı Android sürümlerinde izin, ayarlardan dönüldükten biraz sonra görünür.
        ui.postDelayed(() -> {
            if (Settings.canDrawOverlays(this)) {
                startOverlay();
            } else {
                Toast.makeText(this, Texts.permissionDenied(), Toast.LENGTH_LONG).show();
                showInApp();
            }
        }, 600);
    }

    private void startOverlay() {
        OverlayService.start(this, launchParams);
        finish();
    }

    // --- Uygulama içi mod ---

    private void showInApp() {
        if (page != null) return;
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        if (getSystemService(TV_INPUT_SERVICE) != null) {
            tvView = new TvView(this);
            tvView.setCallback(new TvView.TvInputCallback() {
                @Override public void onConnectionFailed(String inputId) { page.status("inputError"); retuneLater(); }
                @Override public void onDisconnected(String inputId) { page.status("inputError"); retuneLater(); }
                @Override public void onVideoAvailable(String inputId) { retuneAttempts = 0; page.status("playing"); }
                @Override public void onVideoUnavailable(String inputId, int reason) { page.status("inputError"); }
            });
            root.addView(tvView);
        }

        page = new TvPage(this, this, launchParams);
        root.addView(page.webView);
        setContentView(root);
        page.load();
        page.webView.requestFocus();
    }

    @Override
    public void showHdmi(int port) {
        String id = TvPage.hdmiInputId(this, port);
        if (tvView == null || id == null) {
            page.status("sourceError");
            return;
        }
        retuneAttempts = 0;
        tune(id);
    }

    /** Bazı TV'ler (ör. TCL) uygulama arka plana gidince HDMI'yi bırakır; öne gelince görüntü yeniden açılır. */
    @Override
    protected void onResume() {
        super.onResume();
        if (tvView != null && tunedInput != null) tune(tunedInput);
    }

    /** Bağlantı koptuysa birkaç kez, gittikçe seyrek yeniden dener. */
    private void retuneLater() {
        if (tvView == null || tunedInput == null || retuneAttempts >= 5) return;
        retuneAttempts++;
        String id = tunedInput;
        ui.postDelayed(() -> { if (id.equals(tunedInput)) tune(id); }, 1500L * retuneAttempts);
    }

    private void tune(String id) {
        tunedInput = id;
        tvView.tune(id, TvContract.buildChannelUriForPassthroughInput(id));
    }

    @Override
    public void exit() { finish(); }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        OverlayMode.remember(this, intent);
        String params = paramsOf(intent);
        if (params.isEmpty()) return;
        launchParams = params;
        if (page != null) page.relaunch(params);
    }

    private static String paramsOf(Intent intent) {
        String params = intent == null ? null : intent.getStringExtra("params");
        return params == null ? "" : params;
    }

    /** Geri ve renk tuşlarını sayfaya bildirir; diğerleri WebView'e kendiliğinden gider. */
    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int code = pageKey(event.getKeyCode());
        if (code == 0 || page == null) return super.dispatchKeyEvent(event);
        if (event.getAction() == KeyEvent.ACTION_DOWN) page.key(code);
        return true;
    }

    private static int pageKey(int keyCode) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_BACK: return 4;
            case KeyEvent.KEYCODE_PROG_RED: return 403;
            case KeyEvent.KEYCODE_PROG_GREEN: return 404;
            case KeyEvent.KEYCODE_PROG_BLUE: return 406;
            default: return 0;
        }
    }

    @Override
    protected void onDestroy() {
        ui.removeCallbacksAndMessages(null);
        if (tvView != null) tvView.reset();
        if (page != null) page.destroy();
        super.onDestroy();
    }
}
