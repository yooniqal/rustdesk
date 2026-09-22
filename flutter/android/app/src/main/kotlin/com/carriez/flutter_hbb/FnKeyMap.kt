package com.carriez.flutter_hbb

// CubeRemote: 물리 키보드의 F키 자리를 Fn 없이 F1~F12 로 보낸다.
//
// 갤럭시 탭 북커버 키보드는 F1~F12 자리가 기본으로 밝기·음량 같은 미디어 키를 보내고, Fn 을 같이
// 눌러야 F키가 된다. 미디어 키는 대부분 안드로이드가 앱보다 먼저 소비하므로(음량·밝기), 접근성 키
// 필터(KeyCaptureService)가 켜져 있어야 이 변환이 전부 동작한다.
//
// 키보드마다 미디어 키 배치가 달라 표를 박아 넣지 않고 **학습**한다: 사용자가 F1 자리부터 F12 자리까지
// 차례로(Fn 없이) 누르면 그때 들어온 keyCode 를 기억한다. SharedPreferences 에 남는다.

import android.content.Context
import android.util.Log
import android.view.KeyEvent
import android.widget.Toast

object FnKeyMap {
    private const val TAG = "CubeKeys"
    private const val PREFS = "cube_fn_keys"
    private const val KEY_MAP = "map"        // "220:131,221:132,..."  (미디어 keyCode → F keyCode)
    private const val KEY_ENABLED = "enabled"

    private val fKeyCodes = intArrayOf(
        KeyEvent.KEYCODE_F1, KeyEvent.KEYCODE_F2, KeyEvent.KEYCODE_F3, KeyEvent.KEYCODE_F4,
        KeyEvent.KEYCODE_F5, KeyEvent.KEYCODE_F6, KeyEvent.KEYCODE_F7, KeyEvent.KEYCODE_F8,
        KeyEvent.KEYCODE_F9, KeyEvent.KEYCODE_F10, KeyEvent.KEYCODE_F11, KeyEvent.KEYCODE_F12,
    )
    // 리눅스 evdev 스캔코드. Flutter 는 scanCode 로 물리 키를 정하므로 F키 것으로 맞춰 준다.
    private val fScanCodes = intArrayOf(59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 87, 88)

    @Volatile private var map: Map<Int, Int> = emptyMap()
    @Volatile var enabled = false
        private set
    // 학습 중이면 다음에 배울 F키 번호(0 = F1). -1 이면 학습 중 아님.
    @Volatile private var learning = -1
    private val learned = LinkedHashMap<Int, Int>()

    fun load(ctx: Context) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        map = parse(p.getString(KEY_MAP, "") ?: "")
        enabled = p.getBoolean(KEY_ENABLED, false) && map.isNotEmpty()
        Log.i(TAG, "FnKeyMap loaded: ${map.size} keys, enabled=$enabled")
    }

    fun setEnabled(ctx: Context, on: Boolean): Boolean {
        if (on && map.isEmpty()) return false
        enabled = on
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, on).apply()
        return true
    }

    fun startLearning(ctx: Context) {
        learned.clear()
        learning = 0
        Toast.makeText(ctx, "물리 키보드에서 Fn 없이 F1 자리 키를 누르세요 (Esc: 취소)", Toast.LENGTH_LONG).show()
    }

    val isLearning get() = learning >= 0

    // 학습 중 눌린 키. true 를 돌려주면 호출 측이 이 키를 삼킨다.
    fun onLearnKey(ctx: Context, e: KeyEvent): Boolean {
        if (learning < 0) return false
        if (e.action != KeyEvent.ACTION_DOWN) return true
        if (e.repeatCount > 0) return true
        val code = e.keyCode
        if (KeyEvent.isModifierKey(code)) return false
        if (code == KeyEvent.KEYCODE_ESCAPE || code == KeyEvent.KEYCODE_BACK) {
            learning = -1
            Toast.makeText(ctx, "F키 학습 취소", Toast.LENGTH_SHORT).show()
            return true
        }
        if (code in fKeyCodes) {
            // 이미 F키로 들어온다 = 이 키보드는 Fn 없이 F키를 보낸다(또는 Fn 을 같이 눌렀다). 그대로 기록.
            Log.i(TAG, "learn F${learning + 1}: already F key ($code)")
        } else {
            learned[code] = fKeyCodes[learning]
            Log.i(TAG, "learn F${learning + 1}: keyCode=$code scanCode=${e.scanCode}")
        }
        learning++
        if (learning >= fKeyCodes.size) {
            learning = -1
            map = LinkedHashMap(learned)
            enabled = map.isNotEmpty()
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_MAP, map.entries.joinToString(",") { "${it.key}:${it.value}" })
                .putBoolean(KEY_ENABLED, enabled).apply()
            Toast.makeText(ctx, "F키 학습 완료 (${map.size}개 변환). 이제 Fn 없이 F키가 원격으로 갑니다", Toast.LENGTH_LONG).show()
        } else {
            Toast.makeText(ctx, "F${learning + 1} 자리 키를 누르세요", Toast.LENGTH_SHORT).show()
        }
        return true
    }

    fun mapsKey(keyCode: Int): Boolean = enabled && map.containsKey(keyCode)

    // 미디어 키 이벤트를 같은 시각·상태의 F키 이벤트로 바꾼다.
    fun translate(e: KeyEvent): KeyEvent {
        val f = map[e.keyCode] ?: return e
        val idx = fKeyCodes.indexOf(f)
        return KeyEvent(e.downTime, e.eventTime, e.action, f, e.repeatCount, e.metaState,
            e.deviceId, if (idx >= 0) fScanCodes[idx] else e.scanCode, e.flags, e.source)
    }

    private fun parse(s: String): Map<Int, Int> {
        val m = LinkedHashMap<Int, Int>()
        for (pair in s.split(',')) {
            val kv = pair.split(':')
            if (kv.size == 2) {
                val k = kv[0].toIntOrNull(); val v = kv[1].toIntOrNull()
                if (k != null && v != null) m[k] = v
            }
        }
        return m
    }
}
