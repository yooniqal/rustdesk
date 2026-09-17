import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class CubeDevice {
  CubeDevice(Map<String, dynamic> data)
      : id = (data['deviceId'] ?? '').toString(),
        name = (data['name'] ?? '이름 없음').toString(),
        region = (data['region'] ?? '').toString().trim(),
        platform = (data['platform'] ?? '').toString(),
        online = data['online'] == true,
        state = const ['ready', 'attention', 'offline', 'unreported']
                .contains(data['state'])
            ? data['state'] as String
            : data['online'] == true
                ? 'unreported'
                : 'offline',
        reason = (data['reason'] ?? '').toString(),
        lastSeen = data['lastSeen'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (data['lastSeen'] as num).toInt())
            : null;

  final String id, name, region, platform, state, reason;
  final bool online;
  final DateTime? lastSeen;
  String get regionLabel => region.isEmpty ? '지역미지정' : region;
  String get statusLabel => switch (state) {
        'ready' => '준비됨',
        'attention' => '점검 필요',
        'offline' => '오프라인',
        _ => '상태 미보고',
      };
  String get statusDescription => switch (reason) {
        'executable_missing' => '원격 프로그램을 찾을 수 없습니다',
        'service_missing' => '원격 서비스가 설치되어 있지 않습니다',
        'service_stopped' => '원격 서비스가 중지되어 있습니다',
        'relay_disconnected' => '중계 서버에 연결되어 있지 않습니다',
        'config_drift' => '원격 서버 설정을 점검해야 합니다',
        'relay_unverified' => '서비스 정상 · 중계 연결 확인 불가',
        'ready' => '서비스와 중계 연결 정상',
        'heartbeat_stale' => '최근 기기 응답이 없습니다',
        _ => online ? '기기 응답 있음 · 상세 상태 미보고' : '최근 기기 응답이 없습니다',
      };

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        region.toLowerCase().contains(q) ||
        id
            .replaceAll(RegExp(r'[\s-]'), '')
            .contains(q.replaceAll(RegExp(r'[\s-]'), ''));
  }
}

List<CubeDevice> decodeCubeDevices(String body) {
  final data = jsonDecode(body);
  if (data is! List) throw const FormatException('기기 목록 형식이 올바르지 않습니다');
  return data.map((row) {
    if (row is! Map<String, dynamic> ||
        row['deviceId'] is! String ||
        (row['deviceId'] as String).trim().isEmpty) {
      throw const FormatException('기기 정보 형식이 올바르지 않습니다');
    }
    return CubeDevice(row);
  }).toList(growable: false);
}

List<MapEntry<String, List<CubeDevice>>> groupCubeDevices(
    List<CubeDevice> devices) {
  final groups = <String, List<CubeDevice>>{};
  for (final device in devices) {
    (groups[device.regionLabel] ??= []).add(device);
  }
  final unassigned = groups.remove('지역미지정');
  if (unassigned != null) groups['지역미지정'] = unassigned;
  return groups.entries.toList(growable: false);
}

/// Coalesce refreshes and retain the last successful list on transient failure.
class CubeDeviceDirectory extends ChangeNotifier {
  CubeDeviceDirectory(this.fetch);
  final Future<List<CubeDevice>> Function() fetch;
  List<CubeDevice> devices = [];
  bool loading = false;
  String? error;
  DateTime? updatedAt;
  Future<void>? _inFlight;
  bool _disposed = false;

  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (_inFlight != null) return _inFlight!;
    final completion = Completer<void>();
    _inFlight = completion.future;
    _refresh().then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  Future<void> _refresh() async {
    loading = true;
    notifyListeners();
    try {
      final result = await fetch();
      if (_disposed) return;
      devices = result;
      error = null;
      updatedAt = DateTime.now();
    } catch (e) {
      if (!_disposed)
        error = e is CubeDirectoryError
            ? e.message
            : '목록을 갱신하지 못했습니다. 연결 상태를 확인해 주세요.';
    } finally {
      _inFlight = null;
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class CubeDirectoryError implements Exception {
  const CubeDirectoryError(this.message);
  final String message;
}
