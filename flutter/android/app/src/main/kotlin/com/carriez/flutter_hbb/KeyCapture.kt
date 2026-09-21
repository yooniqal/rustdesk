package com.carriez.flutter_hbb

// CubeRemote: 원격 화면이 떠 있는 동안 물리 키보드의 시스템 단축키(Alt+Tab, Win 조합)를
// 안드로이드가 아니라 원격 PC 로 보내기 위한 장치 세 가지를 한곳에 모은다.
//
//  1. Android 16 QPR(API 36.1)+ : 공식 키보드 캡처 — WindowManager.LayoutParams.setKeyboardCaptureEnabled
//     + CAPTURE_KEYBOARD(normal 권한). compileSdk 를 올리지 않으려고 리플렉션으로 부른다.
//  2. 삼성 : SemWindowManager.requestMetaKeyEvent(ComponentName, boolean) — Moonlight 가 쓰는 비공개 OEM API.
//     Win(메타) 키를 앱으로 넘겨준다. 없는 기기에서는 조용히 넘어간다.
//  3. 그 외 : 접근성 키 필터(KeyCaptureService). 접근성 필터는 입력 파이프라인에서
//     PhoneWindowManager.interceptKeyBeforeDispatching(Alt+Tab 을 최근 앱으로 바꾸는 곳)보다 앞에 있어,
//     Activity.dispatchKeyEvent 로는 못 막던 조합을 먼저 가로챌 수 있다. 사용자가 접근성에서 직접 켜야 한다.
//
// 2026-07 진단: dispatchKeyEvent 에서 true 를 돌려줘도 삼성 정책이 먼저 소비해 최근 앱이 떴다.

import android.app.Activity
import android.content.ComponentName
import android.util.Log
import android.view.KeyEvent
import android.view.WindowManager

object KeyCapture {
    private const val TAG = "CubeKeys"

    // 원격 화면(RemotePage)이 열려 있고 키보드 입력이 허용된 동안만 true.
    @Volatile
    var wanted = false
        private set

    // MainActivity 가 화면 앞에 있고 포커스를 가진 동안만 true. 다른 앱 위에서 키를 삼키지 않기 위해서다.
    @Volatile
    var activityFocused = false

    @Volatile
    private var activity: MainActivity? = null

    fun attach(a: MainActivity) { activity = a }
    fun detach(a: MainActivity) { if (activity === a) { activity = null; activityFocused = false } }

    fun setWanted(a: Activity, on: Boolean): Map<String, Any> {
        wanted = on
        val official = setOfficialCapture(a, on)
        val samsung = if (official) false else setSamsungMetaCapture(a, on)
        Log.i(TAG, "capture wanted=$on official=$official samsung=$samsung accessibility=${KeyCaptureService.isOpen}")
        return mapOf("official" to official, "samsung" to samsung, "accessibility" to KeyCaptureService.isOpen)
    }

    private fun setOfficialCapture(a: Activity, on: Boolean): Boolean = try {
        val lp = a.window.attributes
        WindowManager.LayoutParams::class.java
            .getMethod("setKeyboardCaptureEnabled", Boolean::class.javaPrimitiveType)
            .invoke(lp, on)
        a.window.attributes = lp
        true
    } catch (e: NoSuchMethodException) {
        false
    } catch (e: Throwable) {
        Log.w(TAG, "setKeyboardCaptureEnabled failed: $e")
        false
    }

    private fun setSamsungMetaCapture(a: Activity, on: Boolean): Boolean = try {
        val cls = Class.forName("com.samsung.android.view.SemWindowManager")
        val manager = cls.getMethod("getInstance").invoke(null)
        if (manager == null) false else {
            cls.getDeclaredMethod("requestMetaKeyEvent", ComponentName::class.java, Boolean::class.javaPrimitiveType)
                .invoke(manager, a.componentName, on)
            true
        }
    } catch (e: ClassNotFoundException) {
        false
    } catch (e: Throwable) {
        Log.w(TAG, "requestMetaKeyEvent failed: $e")
        false
    }

    // 접근성 필터가 가로챌 키인가. 최소한만 잡는다 — 전부 삼키면 물리 키보드의 한글 조합(IME)과
    // 볼륨·전원 같은 기기 키까지 죽는다. Alt 자체의 눌림/뗌은 평소 경로로 이미 앱에 전달된다.
    fun isSystemShortcut(e: KeyEvent): Boolean {
        val code = e.keyCode
        if (code == KeyEvent.KEYCODE_META_LEFT || code == KeyEvent.KEYCODE_META_RIGHT) return true
        if (e.isMetaPressed) return true
        if (e.isAltPressed && (code == KeyEvent.KEYCODE_TAB || code == KeyEvent.KEYCODE_ESCAPE ||
                    code == KeyEvent.KEYCODE_F4 || code == KeyEvent.KEYCODE_SPACE)) return true
        if (e.isCtrlPressed && e.isShiftPressed && code == KeyEvent.KEYCODE_ESCAPE) return true
        return false
    }

    // 눌림을 가로챈 키는 뗌도 끝까지 가로챈다(Alt 를 먼저 떼도 Tab 뗌이 안드로이드로 새지 않게).
    private val held = HashSet<Int>()

    // KeyCaptureService.onKeyEvent 에서 호출. true = 안드로이드에 넘기지 않고 앱(Flutter)으로 직접 전달했다.
    fun onFilteredKey(e: KeyEvent): Boolean {
        val a = activity
        val up = e.action == KeyEvent.ACTION_UP
        if (up && held.remove(e.keyCode)) {
            a?.deliverCapturedKey(e)
            return true
        }
        if (!wanted || !activityFocused || a == null) {
            if (held.isNotEmpty() && (!wanted || !activityFocused)) held.clear()
            return false
        }
        if (e.action != KeyEvent.ACTION_DOWN || !isSystemShortcut(e)) return false
        held.add(e.keyCode)
        a.deliverCapturedKey(e)
        return true
    }
}
