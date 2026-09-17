import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/mobile_pointer_router.dart';

class FilteredTap extends TapGestureRecognizer with RemotePointerFilter {}

class FilteredScale extends ScaleGestureRecognizer with RemotePointerFilter {}

void main() {
  test('screen hover never moves the cursor in mouse mode', () {
    final router = MobilePointerRouter();
    expect(router.isMouseHover(const PointerHoverEvent(device: 0)), isFalse);
    expect(router.isMouseHover(const PointerHoverEvent(
        kind: PointerDeviceKind.mouse, device: 0)), isTrue);
  });
  test('touch remains a gesture even when mouse and finger share device zero',
      () {
    final router = MobilePointerRouter();
    router.down(const PointerDownEvent(
        kind: PointerDeviceKind.mouse, device: 0, pointer: 1));
    expect(router.down(const PointerDownEvent(device: 0, pointer: 2)), isFalse);
    expect(router.down(const PointerDownEvent(device: 1, pointer: 3)), isFalse);
    expect(router.isMousePointer(const PointerMoveEvent(pointer: 1)), isTrue);
    expect(router.isMousePointer(const PointerMoveEvent(pointer: 2)), isFalse);
    expect(router.end(const PointerCancelEvent(pointer: 1)), isTrue);
    expect(router.end(const PointerUpEvent(pointer: 1)), isFalse);
  });

  test('mouse and normalized touchpad clicks do not need a hover', () {
    final router = MobilePointerRouter();
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.trackpad]) {
      expect(router.down(PointerDownEvent(kind: kind, pointer: 1)), isTrue);
      expect(router.end(const PointerUpEvent(pointer: 1)), isTrue);
    }
  });

  testWidgets('hover cannot steal finger taps or two-finger gestures',
      (tester) async {
    final router = MobilePointerRouter();
    var taps = 0, rawClicks = 0, maxFingers = 0;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Listener(
        onPointerDown: (event) {
          if (router.down(event)) rawClicks++;
        },
        onPointerUp: router.end,
        onPointerCancel: router.end,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            FilteredTap: GestureRecognizerFactoryWithHandlers<FilteredTap>(
              () =>
                  FilteredTap()..acceptPointer = (e) => !router.isMouseDown(e),
              (instance) => instance.onTap = () => taps++,
            ),
            FilteredScale: GestureRecognizerFactoryWithHandlers<FilteredScale>(
              () => FilteredScale()
                ..acceptPointer = (e) => !router.isMouseDown(e),
              (instance) => instance.onUpdate = (details) {
                if (details.pointerCount > maxFingers)
                  maxFingers = details.pointerCount;
              },
            ),
          },
          child: const SizedBox.expand(),
        ),
      ),
    ));
    const pos = Offset(100, 100);
    // Samsung/Flutter: mouse hover and the first screen finger both use ID 0.
    await tester.sendEventToBinding(const PointerHoverEvent(
        kind: PointerDeviceKind.mouse, device: 0, position: pos));
    await tester.sendEventToBinding(const PointerHoverEvent(
        kind: PointerDeviceKind.touch, device: 0, position: pos));
    await tester.sendEventToBinding(const PointerDownEvent(
        pointer: 1, device: 0, position: pos, buttons: kPrimaryButton));
    await tester.sendEventToBinding(
        const PointerUpEvent(pointer: 1, device: 0, position: pos));
    await tester.pump();
    expect(taps, 1);
    expect(rawClicks, 0);
    final first = await tester.startGesture(pos, pointer: 2);
    final second =
        await tester.startGesture(const Offset(200, 100), pointer: 3);
    await first.moveBy(const Offset(0, 40));
    await second.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(maxFingers, 2);
    expect(rawClicks, 0);
    await first.up();
    await second.up();
    await tester.sendEventToBinding(const PointerDownEvent(
        kind: PointerDeviceKind.mouse,
        pointer: 4,
        device: 0,
        position: pos,
        buttons: kPrimaryButton));
    await tester.sendEventToBinding(const PointerUpEvent(
        kind: PointerDeviceKind.mouse, pointer: 4, device: 0, position: pos));
    await tester.pump();
    expect(taps, 1);
    expect(rawClicks, 1);
  });
}
