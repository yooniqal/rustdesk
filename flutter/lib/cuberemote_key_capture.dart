// CubeRemote: 원격 화면 동안 물리 키보드의 시스템 단축키(Alt+Tab, Win 조합)를 원격으로 보낸다.
// 네이티브 쪽 설명은 android/.../KeyCapture.kt. 안드로이드 전용이고 실패해도 원격 세션에는 영향이 없다.

import 'package:flutter/foundation.dart';

import 'common.dart';

class CubeKeyCapture {
  // 원격 화면이 둘 이상 열릴 수 있으므로 마지막 하나가 닫힐 때만 끈다.
  static int _active = 0;

  static Future<void> setEnabled(bool on) async {
    if (!isAndroid) return;
    if (on) {
      _active++;
      if (_active > 1) return;
    } else {
      if (_active == 0) return;
      _active--;
      if (_active > 0) return;
    }
    try {
      await gFFI.invokeMethod('cr_set_key_capture', {'on': on});
    } catch (e) {
      debugPrint('CubeKeyCapture.setEnabled failed: $e');
    }
  }

  // 접근성 설정을 연다. '설치된 앱 › 큐브원격 물리 키보드' 를 켜야 Alt+Tab 이 원격으로 간다.
  static Future<void> openSettings() async {
    if (!isAndroid) return;
    showToast('설치된 앱 › "큐브원격 물리 키보드" 를 켜세요');
    try {
      await gFFI.invokeMethod('cr_open_key_capture_settings');
    } catch (e) {
      debugPrint('CubeKeyCapture.openSettings failed: $e');
    }
  }
}
