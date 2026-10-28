// CubeRemote 콘솔 뷰어 API 클라이언트.
//
// 예전에는 cuberemote_config.dart 에 뷰어 토큰과 가맹점 공통 비밀번호가 평문 상수로 들어 있어
// APK 를 가진 사람이 전 가맹점에 접속할 수 있었다. 이제 운영자가 접속코드로 로그인하면 콘솔이
// 토큰을 발급하고(콘솔 [접속기록]에서 회수 가능), 접속 비밀번호는 접속 직전에 기기별로 받아간다.
// 토큰은 RustDesk 로컬 옵션(기기 안 설정 파일)에 저장한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'cuberemote_config.dart';
import 'models/platform_model.dart';

/// 토큰이 없거나 콘솔이 거부(401)한 경우. 화면은 로그인 폼으로 돌아가야 한다.
class CubeAuthException implements Exception {
  final String message;
  CubeAuthException(this.message);
  @override
  String toString() => message;
}

class CubeViewerApi {
  static const _kToken = 'cube-viewer-token';
  static const _kOperator = 'cube-viewer-operator';
  static const _timeout = Duration(seconds: 12);

  /// 원격 화면 하단바·알림에 표시할 가맹점 이름. 가맹점 탭에서 접속할 때 채운다.
  static final Map<String, String> peerNames = {};

  static String? _buildNumber;

  static String get token => bind.mainGetLocalOption(key: _kToken);
  static String get operator => bind.mainGetLocalOption(key: _kOperator);
  static bool get loggedIn => token.isNotEmpty;

  static Uri _u(String path) => Uri.parse('${CubeRemoteConfig.consoleUrl}$path');

  /// 콘솔 접속기록에 남는 단말 설명. 모델명은 플러그인 없이 못 얻으니 OS·버전만.
  static Future<String> clientLabel() async {
    _buildNumber ??= (await PackageInfo.fromPlatform()).buildNumber;
    return '${Platform.operatingSystem} app $_buildNumber';
  }

  static Future<int?> ownVersionCode() async {
    _buildNumber ??= (await PackageInfo.fromPlatform()).buildNumber;
    return int.tryParse(_buildNumber ?? '');
  }

  static Future<Map<String, String>> _headers() async => {
        'Authorization': 'Bearer $token',
        'X-Viewer-Client': await clientLabel(),
        'Content-Type': 'application/json',
      };

  static dynamic _decode(http.Response res) {
    if (res.statusCode == 401) {
      throw CubeAuthException('로그인이 만료되었습니다. 접속코드를 다시 입력하세요.');
    }
    if (res.statusCode == 403) {
      throw CubeAuthException('운영자 로그인이 필요합니다.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String detail = '';
      try {
        detail = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['error']?.toString() ?? '';
      } catch (_) {}
      throw '서버 응답 ${res.statusCode}${detail.isEmpty ? '' : ' ($detail)'}';
    }
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  static Future<void> login(String code) async {
    final res = await http
        .post(_u('/api/viewer/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code, 'client': await clientLabel()}))
        .timeout(_timeout);
    if (res.statusCode == 401) throw '접속코드가 올바르지 않습니다.';
    if (res.statusCode == 503) throw '콘솔에 운영자 로그인이 설정되지 않았습니다(VIEWER_LOGINS).';
    final body = _decode(res) as Map;
    await bind.mainSetLocalOption(key: _kToken, value: body['token'].toString());
    await bind.mainSetLocalOption(
        key: _kOperator, value: (body['operator'] ?? '').toString());
  }

  /// 콘솔의 토큰도 지운다(실패해도 로컬은 지운다).
  static Future<void> logout() async {
    if (loggedIn) {
      try {
        await http
            .post(_u('/api/viewer/logout'), headers: await _headers())
            .timeout(_timeout);
      } catch (e) {
        debugPrint('viewer logout: $e');
      }
    }
    await bind.mainSetLocalOption(key: _kToken, value: '');
    await bind.mainSetLocalOption(key: _kOperator, value: '');
  }

  static Future<List<dynamic>> devices() async {
    if (!loggedIn) throw CubeAuthException('로그인이 필요합니다.');
    final res = await http
        .get(_u('/api/viewer/devices'), headers: await _headers())
        .timeout(_timeout);
    return _decode(res) as List<dynamic>;
  }

  /// 접속 직전에 받는 기기별 비밀번호.
  static Future<String> credential(String deviceId) async {
    if (!loggedIn) throw CubeAuthException('로그인이 필요합니다.');
    final res = await http
        .get(_u('/api/viewer/devices/$deviceId/credential'),
            headers: await _headers())
        .timeout(_timeout);
    return ((_decode(res) as Map)['password'] ?? '').toString();
  }

  /// 일회성 지원 요청 — 콘솔 /s 의 지원 프로그램이 지금 켜져 있는 PC(cuberemote_support_reporter.dart).
  static Future<List<dynamic>> supportRequests() async {
    if (!loggedIn) throw CubeAuthException('로그인이 필요합니다.');
    final res = await http
        .get(_u('/api/viewer/support'), headers: await _headers())
        .timeout(_timeout);
    return _decode(res) as List<dynamic>;
  }

  /// 지원 프로그램이 마지막으로 보고한 일회용 비밀번호. 프로그램이 닫혔으면 404 → 예외.
  static Future<String> supportCredential(String id) async {
    if (!loggedIn) throw CubeAuthException('로그인이 필요합니다.');
    final res = await http
        .get(_u('/api/viewer/support/$id/credential'), headers: await _headers())
        .timeout(_timeout);
    if (res.statusCode == 404) throw '지원 프로그램이 닫혔습니다.';
    return ((_decode(res) as Map)['password'] ?? '').toString();
  }

  /// 접속 기록 시작. 기록은 부가 기능이므로 실패해도 세션을 막지 않는다(null).
  static Future<int?> sessionStart(String deviceId) async {
    if (!loggedIn) return null;
    try {
      final res = await http
          .post(_u('/api/viewer/sessions'),
              headers: await _headers(),
              body: jsonEncode({'event': 'start', 'deviceId': deviceId}))
          .timeout(_timeout);
      final body = _decode(res) as Map?;
      final sid = body?['sessionId'];
      return sid is int ? sid : int.tryParse('$sid');
    } catch (e) {
      debugPrint('viewer session start: $e');
      return null;
    }
  }

  static Future<void> sessionEnd(int? sessionId) async {
    if (sessionId == null || !loggedIn) return;
    try {
      await http
          .post(_u('/api/viewer/sessions'),
              headers: await _headers(),
              body: jsonEncode({'event': 'end', 'sessionId': sessionId}))
          .timeout(_timeout);
    } catch (e) {
      debugPrint('viewer session end: $e');
    }
  }

  /// 콘솔에 올라간 배포본. {version, versionCode, androidAvailable}. 실패하면 null.
  static Future<Map<String, dynamic>?> appVersion() async {
    if (!loggedIn) return null;
    try {
      final res = await http
          .get(_u('/api/viewer/app-version'), headers: await _headers())
          .timeout(_timeout);
      return (_decode(res) as Map).cast<String, dynamic>();
    } catch (e) {
      debugPrint('viewer app-version: $e');
      return null;
    }
  }

  /// 앱 안 "새 버전 설치" 버튼이 여는 주소. 운영자 토큰으로 설치 암호를 건너뛴다.
  static Uri androidDownloadUri() =>
      _u('/app/android?vt=${Uri.encodeQueryComponent(token)}');
}

/// 가맹점 탭이 없는 화면(윈도우·맥 뷰어, ID 직접 입력)에서 비밀번호 없이 접속할 때 한 번 묻는 로그인.
/// 성공하면 true. 취소하면 false — 호출 쪽은 그냥 진행해 RustDesk 가 평소처럼 비밀번호를 묻게 둔다.
Future<bool> cubePromptLogin(BuildContext context) async {
  final controller = TextEditingController();
  String? error;
  bool busy = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      Future<void> submit() async {
        final code = controller.text.trim();
        if (code.isEmpty || busy) return;
        setState(() { busy = true; error = null; });
        try {
          await CubeViewerApi.login(code);
          if (ctx.mounted) Navigator.pop(ctx, true);
        } catch (e) {
          setState(() { busy = false; error = '$e'; });
        }
      }

      return AlertDialog(
        title: const Text('큐브원격 로그인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('관리자에게 받은 접속코드를 입력하면 가맹점 접속 비밀번호를 자동으로 채웁니다.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: '접속코드',
                border: const OutlineInputBorder(),
                errorText: error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('건너뛰기')),
          ElevatedButton(onPressed: busy ? null : submit, child: const Text('로그인')),
        ],
      );
    }),
  );
  controller.dispose();
  return ok == true;
}
