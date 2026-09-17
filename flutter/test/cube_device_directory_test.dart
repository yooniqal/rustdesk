import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/cube_device_directory.dart';

void main() {
  test('legacy online response is unreported, never falsely ready', () {
    final d =
        decodeCubeDevices('[{"deviceId":"123456", "online":true}]').single;
    expect(d.state, 'unreported');
    expect(d.online, isTrue);
    expect(d.matches('123-456'), isTrue);
  });
  test('groups preserve server order with unassigned region last', () {
    final devices = [
      CubeDevice({'deviceId': '1'}),
      CubeDevice({'deviceId': '2', 'region': '부산'}),
      CubeDevice({'deviceId': '3', 'region': '서울'}),
      CubeDevice({'deviceId': '4', 'region': '부산'}),
    ];
    final groups = groupCubeDevices(devices);
    expect(groups.map((g) => g.key), ['부산', '서울', '지역미지정']);
    expect(groups.first.value.map((d) => d.id), ['2', '4']);
  });
  test('malformed responses cannot replace a valid list', () {
    for (final body in ['{}', '[null]', '[{"name":"누락"}]']) {
      expect(() => decodeCubeDevices(body), throwsFormatException);
    }
  });
  test('overlapping refreshes share a request', () async {
    final pending = Completer<List<CubeDevice>>();
    var calls = 0;
    final directory = CubeDeviceDirectory(() {
      calls++;
      return pending.future;
    });
    final a = directory.refresh(), b = directory.refresh();
    expect(identical(a, b), isTrue);
    expect(calls, 1);
    expect(directory.loading, isTrue);
    pending.complete([
      CubeDevice({'deviceId': '1'})
    ]);
    await a;
    expect(directory.devices.single.id, '1');
    expect(directory.loading, isFalse);
    directory.dispose();
  });
  test('failure preserves last good list and timestamp, retry clears error',
      () async {
    var fail = false;
    final directory = CubeDeviceDirectory(() async {
      if (fail) throw const CubeDirectoryError('일시적인 연결 오류');
      return [
        CubeDevice({'deviceId': '1'})
      ];
    });
    await directory.refresh();
    final last = directory.updatedAt;
    fail = true;
    await directory.refresh();
    expect(directory.devices.single.id, '1');
    expect(directory.updatedAt, last);
    expect(directory.error, '일시적인 연결 오류');
    fail = false;
    await directory.refresh();
    expect(directory.error, isNull);
    directory.dispose();
  });
  test('a synchronous fetch failure does not prevent retries', () async {
    var calls = 0;
    final directory = CubeDeviceDirectory(() {
      calls++;
      if (calls == 1) throw const CubeDirectoryError('오류');
      return Future.value([
        CubeDevice({'deviceId': '2'})
      ]);
    });
    await directory.refresh();
    await directory.refresh();
    expect(calls, 2);
    expect(directory.devices.single.id, '2');
    directory.dispose();
  });
  test('completion after disposal never notifies or updates the directory',
      () async {
    final pending = Completer<List<CubeDevice>>();
    final directory = CubeDeviceDirectory(() => pending.future);
    var notifications = 0;
    directory.addListener(() {
      notifications++;
    });
    final request = directory.refresh();
    expect(notifications, 1);
    directory.dispose();
    pending.complete([
      CubeDevice({'deviceId': '1'})
    ]);
    await request;
    expect(notifications, 1);
    expect(directory.devices, isEmpty);
  });
}
