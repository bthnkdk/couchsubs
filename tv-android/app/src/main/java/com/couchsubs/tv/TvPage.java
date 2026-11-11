// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import android.content.Context;
import android.graphics.Color;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * LG ve Samsung'la ortak arayüzü çalıştıran şeffaf WebView ve sayfanın "AndroidTV" köprüsü.
 * HDMI'yı nasıl göstereceği kullanana kalır: MainActivity kendi TvView'inde, OverlayService TV'nin kendi giriş
 * ekranının üstünde gösterir.
 */
final class TvPage {
    /** HDMI'yı gösterme ve çıkış, sayfayı barındıran tarafa göre değişir. UI iş parçacığında çağrılır. */
    interface Host {
        void showHdmi(int port);
        void exit();
    }

    final WebView webView;
    private final Context context;
    private final Host host;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private String launchParams;

    TvPage(Context context, Host host, String launchParams) {
        this.context = context;
        this.host = host;
        this.launchParams = launchParams;

        webView = new WebView(context);
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
    }

    void load() {
        webView.loadUrl("file:///android_asset/tv/index.html");
    }

    /** Uygulama yeniden başlatıldı: yeni parametreler sayfaya iletilir. */
    void relaunch(String params) {
        if (params.isEmpty()) return;
        launchParams = params;
        evaluate("window.__onRelaunch(" + quoted(params) + ")");
    }

    void status(String kind) {
        evaluate("window.__onHdmiStatus(" + quoted(kind) + ")");
    }

    void key(int code) {
        evaluate("window.__onKey(" + code + ")");
    }

    void destroy() {
        webView.destroy();
    }

    private void evaluate(String script) {
        ui.post(() -> webView.evaluateJavascript(script, null));
    }

    private static String quoted(String text) {
        return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }

    /** Sayfanın 1920 CSS piksellik genişliğini ekranın fiziksel genişliğine sığdıran WebView ölçeği (yüzde). */
    private int fitScalePercent() {
        DisplayMetrics metrics = new DisplayMetrics();
        WindowManager windows = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        windows.getDefaultDisplay().getRealMetrics(metrics);
        int width = Math.max(metrics.widthPixels, metrics.heightPixels);
        return width > 0 ? Math.max(1, Math.round(width * 100f / 1920f)) : 0;
    }

    /**
     * TV'nin HDMI girişleri, port numarasına göre sıralı. Girişin numarası sıradaki yeridir.
     * HDMI-CEC ile bağlı cihazlar (PS5 gibi) bazı TV'lerde girişin "alt girişi" olarak ayrıca listelenir; onlar sayılmaz,
     * yoksa numaralar kayar ve iki bağlı giriş görünür. Kimlikler sayısal sıralanır ("HW10", "HW2"den sonra gelir).
     */
    static List<TvInputInfo> hdmiInputs(Context context) {
        List<TvInputInfo> inputs = new ArrayList<>();
        TvInputManager manager = (TvInputManager) context.getSystemService(Context.TV_INPUT_SERVICE);
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

    /** 1'den başlayan numaraya karşılık gelen HDMI girişinin kimliği, yoksa null. */
    static String hdmiInputId(Context context, int port) {
        List<TvInputInfo> inputs = hdmiInputs(context);
        return port >= 1 && port <= inputs.size() ? inputs.get(port - 1).getId() : null;
    }

    private class Bridge {
        @JavascriptInterface
        public String launchParams() { return launchParams; }

        @JavascriptInterface
        public void showHdmi(int port) { ui.post(() -> host.showHdmi(port)); }

        /** Tek bağlı HDMI girişi varsa onun numarası, yoksa 0. */
        @JavascriptInterface
        public int consolePort() {
            TvInputManager manager = (TvInputManager) context.getSystemService(Context.TV_INPUT_SERVICE);
            if (manager == null) return 0;
            List<TvInputInfo> inputs = hdmiInputs(context);
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
        public void exit() { ui.post(host::exit); }
    }
}
