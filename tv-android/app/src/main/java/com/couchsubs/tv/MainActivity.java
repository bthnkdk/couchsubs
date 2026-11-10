// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.media.tv.TvContract;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;
import android.media.tv.TvView;
import android.os.Bundle;
import android.util.DisplayMetrics;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.FrameLayout;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * HDMI girişini TvView ile tam ekran gösterir; üstünde şeffaf WebView'de LG ve Samsung'la ortak arayüz çalışır.
 */
public class MainActivity extends Activity {
    private TvView tvView;
    private WebView webView;
    private String launchParams = "";
    /** Son açılan HDMI girişi; uygulama öne gelince ya da bağlantı kopunca yeniden açılır. */
    private String tunedInput;
    private int retuneAttempts;
    private final android.os.Handler handler = new android.os.Handler(android.os.Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        launchParams = paramsOf(getIntent());

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        if (getSystemService(TV_INPUT_SERVICE) != null) {
            tvView = new TvView(this);
            tvView.setCallback(new TvView.TvInputCallback() {
                @Override public void onConnectionFailed(String inputId) { status("inputError"); retuneLater(); }
                @Override public void onDisconnected(String inputId) { status("inputError"); retuneLater(); }
                @Override public void onVideoAvailable(String inputId) { retuneAttempts = 0; status("playing"); }
                @Override public void onVideoUnavailable(String inputId, int reason) { status("inputError"); }
            });
            root.addView(tvView);
        }

        webView = new WebView(this);
        webView.setBackgroundColor(Color.TRANSPARENT);
        webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        // Türkçe dublaj: bilgisayardan gelen ses kumandaya basılmadan çalabilsin.
        settings.setMediaPlaybackRequiresUserGesture(false);
        // Sayfanın 1920 piksellik viewport'u kullanılır ve ekrana sığdırılır (bkz. index.html); yoksa yazılar iki kat büyük.
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportZoom(false);
        // Ölçek fiziksel piksel başına yüzde: 1920 CSS pikseli ekranın tam genişliğine sığar (1080p'de %100).
        webView.setInitialScale(fitScalePercent());
        webView.addJavascriptInterface(new Bridge(), "AndroidTV");
        root.addView(webView);
        setContentView(root);
        webView.loadUrl("file:///android_asset/tv/index.html");
        webView.requestFocus();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        String params = paramsOf(intent);
        if (!params.isEmpty()) {
            launchParams = params;
            evaluate("window.__onRelaunch(" + quoted(params) + ")");
        }
    }

    /** Sayfanın 1920 CSS piksellik genişliğini ekranın fiziksel genişliğine sığdıran WebView ölçeği (yüzde). */
    private int fitScalePercent() {
        DisplayMetrics metrics = new DisplayMetrics();
        getWindowManager().getDefaultDisplay().getRealMetrics(metrics);
        int width = Math.max(metrics.widthPixels, metrics.heightPixels);
        return width > 0 ? Math.max(1, Math.round(width * 100f / 1920f)) : 0;
    }

    private static String paramsOf(Intent intent) {
        String params = intent == null ? null : intent.getStringExtra("params");
        return params == null ? "" : params;
    }

    /** Geri ve renk tuşlarını sayfaya bildirir; diğerleri WebView'e kendiliğinden gider. */
    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int code = pageKey(event.getKeyCode());
        if (code == 0) return super.dispatchKeyEvent(event);
        if (event.getAction() == KeyEvent.ACTION_DOWN) evaluate("window.__onKey(" + code + ")");
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
        handler.postDelayed(() -> { if (id.equals(tunedInput)) tune(id); }, 1500L * retuneAttempts);
    }

    private void tune(String id) {
        tunedInput = id;
        tvView.tune(id, TvContract.buildChannelUriForPassthroughInput(id));
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (tvView != null) tvView.reset();
        webView.destroy();
        super.onDestroy();
    }

    private void status(String kind) {
        evaluate("window.__onHdmiStatus(" + quoted(kind) + ")");
    }

    private void evaluate(String script) {
        runOnUiThread(() -> webView.evaluateJavascript(script, null));
    }

    private static String quoted(String text) {
        return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }

    /**
     * TV'nin HDMI girişleri, port numarasına göre sıralı. Girişin numarası sıradaki yeridir.
     * HDMI-CEC ile bağlı cihazlar (PS5 gibi) bazı TV'lerde girişin "alt girişi" olarak ayrıca listelenir; onlar sayılmaz,
     * yoksa numaralar kayar ve iki bağlı giriş görünür. Kimlikler sayısal sıralanır ("HW10", "HW2"den sonra gelir).
     */
    private List<TvInputInfo> hdmiInputs() {
        List<TvInputInfo> inputs = new ArrayList<>();
        TvInputManager manager = (TvInputManager) getSystemService(TV_INPUT_SERVICE);
        if (manager == null) return inputs;
        for (TvInputInfo input : manager.getTvInputList()) {
            if (input.getType() == TvInputInfo.TYPE_HDMI && input.isPassthroughInput() && input.getParentId() == null) {
                inputs.add(input);
            }
        }
        Collections.sort(inputs, Comparator.comparingLong((TvInputInfo input) -> lastNumber(input.getId()))
                .thenComparing(TvInputInfo::getId));
        return inputs;
    }

    /** Kimliğin sonundaki sayı ("…/HW15" → 15); yoksa en sona konur. */
    static long lastNumber(String id) {
        int end = id.length();
        while (end > 0 && !Character.isDigit(id.charAt(end - 1))) end--;
        int start = end;
        while (start > 0 && Character.isDigit(id.charAt(start - 1))) start--;
        if (start == end) return Long.MAX_VALUE;
        try { return Long.parseLong(id.substring(start, end)); } catch (NumberFormatException e) { return Long.MAX_VALUE; }
    }

    private class Bridge {
        @JavascriptInterface
        public String launchParams() { return launchParams; }

        @JavascriptInterface
        public void showHdmi(int port) {
            runOnUiThread(() -> {
                List<TvInputInfo> inputs = hdmiInputs();
                if (tvView == null || port < 1 || port > inputs.size()) {
                    status("sourceError");
                    return;
                }
                retuneAttempts = 0;
                tune(inputs.get(port - 1).getId());
            });
        }

        /** Tek bağlı HDMI girişi varsa onun numarası, yoksa 0. */
        @JavascriptInterface
        public int consolePort() {
            TvInputManager manager = (TvInputManager) getSystemService(TV_INPUT_SERVICE);
            if (manager == null) return 0;
            List<TvInputInfo> inputs = hdmiInputs();
            int found = 0;
            for (int i = 0; i < inputs.size(); i++) {
                if (manager.getInputState(inputs.get(i).getId()) != TvInputManager.INPUT_STATE_CONNECTED) continue;
                if (found != 0) return 0;
                found = i + 1;
            }
            return found;
        }

        @JavascriptInterface
        public String localAddress() {
            try {
                for (NetworkInterface face : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                    if (!face.isUp() || face.isLoopback()) continue;
                    for (InetAddress address : Collections.list(face.getInetAddresses())) {
                        if (address instanceof Inet4Address && address.isSiteLocalAddress()) return address.getHostAddress();
                    }
                }
            } catch (Exception ignored) {
                return "";
            }
            return "";
        }

        @JavascriptInterface
        public void exit() { runOnUiThread(MainActivity.this::finish); }
    }
}
