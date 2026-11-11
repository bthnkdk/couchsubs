// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import java.util.Locale;

/**
 * Overlay modunun açık olup olmadığı. Varsayılan: TCL'de açık (TvView'de görüntü siyah kalıyor), diğerlerinde kapalı.
 * Elle seçmek için: adb shell am start -n com.couchsubs.tv/.MainActivity --es overlay on|off|auto
 */
final class OverlayMode {
    private static final String PREFS = "couchsubs";
    private static final String KEY = "overlay";

    private OverlayMode() {}

    /** Başlatma isteğinde overlay tercihi varsa kaydeder. */
    static void remember(Context context, Intent intent) {
        String value = intent == null ? null : intent.getStringExtra(KEY);
        if (value == null) return;
        value = value.trim().toLowerCase(Locale.ROOT);
        if (!value.equals("on") && !value.equals("off") && !value.equals("auto")) return;
        prefs(context).edit().putString(KEY, value).apply();
    }

    static boolean wanted(Context context) {
        String value = prefs(context).getString(KEY, "auto");
        if (value.equals("on")) return true;
        if (value.equals("off")) return false;
        return isTcl();
    }

    private static boolean isTcl() {
        String maker = (Build.MANUFACTURER + " " + Build.BRAND).toLowerCase(Locale.ROOT);
        return maker.contains("tcl");
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
