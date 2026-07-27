// CubeRemote: 원격/파일전송 세션이 열려 있는 동안 앱 프로세스를 살려두는 헬퍼.
//
// 배경: MainService(포그라운드 서비스)는 "내 화면을 남에게 보여주는" 호스트 세션에서만 뜬다.
// 우리가 쓰는 뷰어 세션(가맹점 PC를 조작)에는 포그라운드 서비스가 없어서, 홈으로 나가거나
// 다른 앱을 잠깐 보고 오면 안드로이드가 프로세스를 정리해 버리고 RemotePage.dispose()가
// sessionClose 를 호출하면서 연결이 끊겼다.
//
// 네이티브 ViewerSessionService 를 세션 동안만 포그라운드로 띄워 이를 막는다.

import 'package:flutter/foundation.dart';

import 'common.dart';

class CubeSessionKeepAlive {
  // 원격 화면과 파일 전송이 동시에 열릴 수 있으므로, 마지막 하나가 닫힐 때만 서비스를 내린다.
  static int _active = 0;

  static Future<void> start(String peer) async {
    if (!isAndroid) return;
    _active++;
    if (_active > 1) return;
    try {
      await gFFI.invokeMethod('cr_start_session_service', {'peer': peer});
    } catch (e) {
      // 서비스가 못 떠도 원격 세션 자체는 계속돼야 한다(화면을 켜둔 채면 정상 동작).
      debugPrint('CubeSessionKeepAlive.start failed: $e');
      _active--;
    }
  }

  static Future<void> stop() async {
    if (!isAndroid) return;
    if (_active == 0) return;
    _active--;
    if (_active > 0) return;
    try {
      await gFFI.invokeMethod('cr_stop_session_service');
    } catch (e) {
      debugPrint('CubeSessionKeepAlive.stop failed: $e');
    }
  }
}
