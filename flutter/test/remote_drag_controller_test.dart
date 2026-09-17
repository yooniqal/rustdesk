import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/remote_drag_controller.dart';

void main() {
  test('cancel before cursor move completes cannot press the remote button',
      () async {
    final events = <bool>[];
    final drag = RemoteDragController((down) async {
      events.add(down);
    });
    final move = Completer<bool>();
    final start = drag.begin(prepare: () => move.future);
    await drag.end();
    move.complete(true);
    await start;
    expect(events, isEmpty);
  });
  test('drag sends one down and one up even after repeated end', () async {
    final events = <bool>[];
    final drag = RemoteDragController((down) async {
      events.add(down);
    });
    await drag.begin();
    await drag.begin();
    await drag.end();
    await drag.end();
    expect(events, [true, false]);
  });
  test('blocked position cannot start a drag', () async {
    final events = <bool>[];
    final drag = RemoteDragController((down) async {
      events.add(down);
    });
    await drag.begin(prepare: () async => false);
    await drag.end();
    expect(events, isEmpty);
  });
  test('a late old move cannot restart a newer completed gesture', () async {
    final events = <bool>[];
    final drag = RemoteDragController((down) async {
      events.add(down);
    });
    final oldMove = Completer<bool>();
    final start = drag.begin(prepare: () => oldMove.future);
    await drag.end();
    await drag.begin();
    await drag.end();
    oldMove.complete(true);
    await start;
    expect(events, [true, false]);
  });
}
