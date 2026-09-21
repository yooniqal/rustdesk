package com.carriez.flutter_hbb

// CubeRemote: 물리 키보드의 시스템 단축키를 원격으로 보내기 위한 접근성 키 필터. 자세한 배경은 KeyCapture.kt.
// 화면 내용을 읽지도, 제스처를 만들지도 않는다 — 키 이벤트만 본다. 원격 화면이 앞에 있을 때만 키를 가로챈다.
// "큐브원격 입력"(InputService, 이 기기를 원격 제어 '당할' 때 쓰는 것)과는 별개의 서비스다.

import android.accessibilityservice.AccessibilityService
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

class KeyCaptureService : AccessibilityService() {
    companion object {
        @Volatile
        var isOpen = false
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        isOpen = true
        Log.i("CubeKeys", "KeyCaptureService connected")
    }

    override fun onKeyEvent(event: KeyEvent): Boolean =
        try {
            KeyCapture.onFilteredKey(event)
        } catch (e: Throwable) {
            Log.w("CubeKeys", "onKeyEvent failed: $e")
            false
        }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        isOpen = false
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        isOpen = false
        super.onDestroy()
    }
}
