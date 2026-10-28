// CubeRemote 일회성 원격 지원 보고.
//
// 콘솔 /s 에서 받은 지원 프로그램은 이 윈도우 빌드를 "cuberemote-support.exe" 로 내려준다.
// 실행 파일 이름에 "support" 가 있을 때만 켜지며, 자기 ID·일회용 비밀번호를 15초마다 콘솔
// /api/support/report 에 올린다. 운영자 앱 가맹점 탭의 "지원 요청" 칸에 뜨고 탭 한 번으로
// 접속한다 — 고객이 번호를 불러 줄 필요가 없다. 창을 닫으면 보고가 끊겨 90초 뒤 목록에서 빠진다.
// 운영자가 평소 쓰는 뷰어(cuberemote-setup.exe 로 설치)에서는 켜지지 않는다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cuberemote_config.dart';
import 'models/platform_model.dart';

class CubeSupportReporter {
  static Timer? _timer;
  static final String _key = _randomKey();
  static String _lastId = '';

  // 배포 exe 는 포터블 압축본이라 실제 실행 파일은 %LOCALAPPDATA% 에 풀린 rustdesk.exe 다.
  // 원래 이름은 압축본이 RUSTDESK_APPNAME 환경변수로 넘겨준다(libs/portable).
  static bool get enabled {
    if (!Platform.isWindows) return false;
    final name = Platform.environment['RUSTDESK_APPNAME'] ??
        Platform.resolvedExecutable.split(RegExp(r'[\\/]')).last;
    return name.toLowerCase().contains('support');
  }

  static String _randomKey() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static void start() {
    if (!enabled || _timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _report());
    // 서비스가 ID 를 받기까지 몇 초 걸린다 — 첫 보고는 조금 뒤에
    Timer(const Duration(seconds: 3), _report);
  }

  static Future<void> _report() async {
    try {
      final id = (await bind.mainGetMyId()).replaceAll(' ', '');
      final password = await bind.mainGetTemporaryPassword();
      if (id.isEmpty || password.isEmpty) return;
      _lastId = id;
      await http
          .post(Uri.parse('${CubeRemoteConfig.consoleUrl}/api/support/report'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'id': id,
                'key': _key,
                'password': password,
                'hostname': Platform.localHostname,
                'username': Platform.environment['USERNAME'] ?? '',
                'os': Platform.operatingSystemVersion,
              }))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('support report: $e');
    }
  }

  /// 창을 닫을 때 바로 목록에서 빼 달라고 알린다(실패해도 90초 뒤 자연히 빠진다).
  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (_lastId.isEmpty) return;
    try {
      await http
          .post(Uri.parse('${CubeRemoteConfig.consoleUrl}/api/support/end'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'id': _lastId, 'key': _key}))
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}
