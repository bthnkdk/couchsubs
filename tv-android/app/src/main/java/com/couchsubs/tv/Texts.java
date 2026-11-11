// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import java.util.Locale;

/** Android tarafının birkaç kısa metni; sayfa metinleri tv-webos/i18n.js'tedir. */
final class Texts {
    private Texts() {}

    private static boolean turkish() {
        return "tr".equals(Locale.getDefault().getLanguage());
    }

    static String overlayRunning() {
        return turkish() ? "Altyazı HDMI görüntüsünün üstünde gösteriliyor" : "Showing subtitles over HDMI";
    }

    static String overlayStopped() {
        return turkish()
                ? "CouchSubs altyazısı kapatıldı. Yeniden açmak için CouchSubs'ı tekrar başlatın."
                : "CouchSubs subtitles stopped. Open CouchSubs again to restart them.";
    }

    static String askPermission() {
        return turkish()
                ? "Altyazının HDMI görüntüsünün üstünde görünmesi için CouchSubs'a \"diğer uygulamaların üzerinde göster\" izni verin."
                : "Allow CouchSubs to \"display over other apps\" so subtitles can appear over HDMI.";
    }

    static String permissionDenied() {
        return turkish()
                ? "İzin verilmedi; HDMI CouchSubs'ın içinde gösteriliyor."
                : "Permission not granted; showing HDMI inside CouchSubs.";
    }
}
