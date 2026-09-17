import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/common/widgets/gestures.dart';

class GestureLog {
  int taps = 0, doubleTaps = 0, rightClicks = 0;
  int pans = 0, panEnds = 0, moves = 0, scales = 0, scaleEnds = 0;
  int dragStarts = 0, dragEnds = 0, dragCancels = 0;
  PointerDeviceKind? panKind;
  Widget build() => Directionality(
        textDirection: TextDirection.ltr,
        child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                      () => TapGestureRecognizer(),
                      (r) => r.onTap = () {
                            taps++;
                          }),
              DoubleTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                      DoubleTapGestureRecognizer>(
                  () => DoubleTapGestureRecognizer(),
                  (r) => r.onDoubleTap = () {
                        doubleTaps++;
                      }),
              DoubleFinerTapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                          DoubleFinerTapGestureRecognizer>(
                      () => DoubleFinerTapGestureRecognizer(),
                      (r) => r.onDoubleFinerTap = (_) {
                            rightClicks++;
                          }),
              HoldTapMoveGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                          HoldTapMoveGestureRecognizer>(
                      () => HoldTapMoveGestureRecognizer(),
                      (r) => r
                        ..onHoldDragStart = (_) {
                          dragStarts++;
                        }
                        ..onHoldDragEnd = (_) {
                          dragEnds++;
                        }
                        ..onHoldDragCancel = () {
                          dragCancels++;
                        }),
              CustomTouchGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                          CustomTouchGestureRecognizer>(
                      () => CustomTouchGestureRecognizer(),
                      (r) => r
                        ..onOneFingerPanStart = (d) {
                          pans++;
                          panKind = d.kind;
                        }
                        ..onOneFingerPanUpdate = (_) {
                          moves++;
                        }
                        ..onOneFingerPanEnd = (_) {
                          panEnds++;
                        }
                        ..onTwoFingerScaleStart = (_) {
                          scales++;
                        }
                        ..onTwoFingerScaleEnd = (_) {
                          scaleEnds++;
                        }),
            },
            child: const SizedBox.expand()),
      );
}

void main() {
  testWidgets('two fingers right-click once and do not block the next tap',
      (tester) async {
    final log = GestureLog();
    await tester.pumpWidget(log.build());
    final a = await tester.startGesture(const Offset(100, 100), pointer: 1);
    final b = await tester.startGesture(const Offset(180, 100), pointer: 2);
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(log.rightClicks, 1);
    expect(log.taps, 0);
    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 350));
    expect(log.taps, 1);
    expect(log.rightClicks, 1);
  });
  testWidgets('sequential double tap never becomes two-finger right click',
      (tester) async {
    final log = GestureLog();
    await tester.pumpWidget(log.build());
    await tester.tapAt(const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 350));
    expect(log.doubleTaps, 1);
    expect(log.rightClicks, 0);
  });
  testWidgets('cancelled two-finger gesture leaves the next tap usable',
      (tester) async {
    final log = GestureLog();
    await tester.pumpWidget(log.build());
    final a = await tester.startGesture(const Offset(100, 100), pointer: 1);
    final b = await tester.startGesture(const Offset(180, 100), pointer: 2);
    await a.cancel();
    await b.cancel();
    await tester.pump(const Duration(milliseconds: 350));
    expect(log.rightClicks, 0);
    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 350));
    expect(log.taps, 1);
  });
  testWidgets(
      'consecutive pans start immediately with touch kind and paired ends',
      (tester) async {
    final log = GestureLog();
    await tester.pumpWidget(log.build());
    for (var i = 1; i <= 2; i++) {
      final finger =
          await tester.startGesture(const Offset(100, 100), pointer: i);
      await finger.moveBy(const Offset(50, 0));
      await finger.moveBy(const Offset(10, 0));
      await finger.up();
    }
    expect(log.pans, 2);
    expect(log.panEnds, 2);
    expect(log.panKind, PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 350));
  });
  testWidgets('lifting one finger after scaling cannot start a cursor pan',
      (tester) async {
    final log = GestureLog();
    await tester.pumpWidget(log.build());
    final a = await tester.startGesture(const Offset(100, 100), pointer: 1);
    final b = await tester.startGesture(const Offset(200, 100), pointer: 2);
    await a.moveBy(const Offset(-50, 0));
    await b.moveBy(const Offset(50, 0));
    expect(log.scales, 1);
    await b.up();
    await a.moveBy(const Offset(20, 0));
    await a.moveBy(const Offset(20, 0));
    expect(log.pans, 0);
    await a.up();
    final c = await tester.startGesture(const Offset(100, 100), pointer: 3);
    await c.moveBy(const Offset(50, 0));
    await c.moveBy(const Offset(10, 0));
    await c.up();
    expect(log.pans, 1);
    expect(log.scaleEnds, 1);
    await tester.pump(const Duration(milliseconds: 350));
  });
  testWidgets('tap then drag releases on cancellation and can be repeated',
      (tester) async {
    final log = GestureLog();
    await tester.pumpWidget(log.build());
    for (var i = 0; i < 2; i++) {
      await tester.tapAt(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 80));
      final finger =
          await tester.startGesture(const Offset(100, 100), pointer: 20 + i);
      await tester.pump(const Duration(milliseconds: 310));
      await finger.moveBy(const Offset(30, 0));
      if (i == 0) {
        await finger.cancel();
      } else {
        await finger.up();
      }
      await tester.pump(const Duration(milliseconds: 350));
    }
    expect(log.dragStarts, 2);
    expect(log.dragCancels, 1);
    expect(log.dragEnds, 1);
    expect(log.rightClicks, 0);
  });
  testWidgets('a third finger cannot produce a right-click', (tester) async {
    final log = GestureLog();
    await tester.pumpWidget(log.build());
    final a = await tester.startGesture(const Offset(100, 100), pointer: 1);
    final b = await tester.startGesture(const Offset(180, 100), pointer: 2);
    final c = await tester.startGesture(const Offset(260, 100), pointer: 3);
    await a.up();
    await b.up();
    await c.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(log.rightClicks, 0);
  });
  testWidgets(
      'three-finger movement cannot turn into zoom while lifting fingers',
      (tester) async {
    final log = GestureLog();
    await tester.pumpWidget(log.build());
    final a = await tester.startGesture(const Offset(100, 100), pointer: 1);
    final b = await tester.startGesture(const Offset(180, 100), pointer: 2);
    final c = await tester.startGesture(const Offset(260, 100), pointer: 3);
    await a.moveBy(const Offset(0, 80));
    await b.moveBy(const Offset(0, 80));
    await c.moveBy(const Offset(0, 80));
    await c.up();
    await a.moveBy(const Offset(-50, 0));
    await b.moveBy(const Offset(50, 0));
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(log.scales, 0);
    expect(log.pans, 0);
    expect(log.rightClicks, 0);
  });
  testWidgets('disposing held contacts cancels pending recognition',
      (tester) async {
    final log = GestureLog();
    await tester.pumpWidget(log.build());
    final a = await tester.startGesture(const Offset(100, 100), pointer: 1);
    final b = await tester.startGesture(const Offset(180, 100), pointer: 2);
    await tester.pumpWidget(const SizedBox());
    await a.cancel();
    await b.cancel();
    await tester.pump(const Duration(milliseconds: 350));
    expect(log.rightClicks, 0);
    expect(tester.takeException(), isNull);
  });
}
