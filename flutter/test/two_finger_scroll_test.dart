import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/two_finger_scroll.dart';

void main() {
  test('parallel movement scrolls without zoom from small finger jitter', () {
    final gesture = TwoFingerScroll();
    expect(gesture.update(1.02, const Offset(0, 8)), TwoFingerIntent.pending);
    expect(gesture.update(1.03, const Offset(0, 10)), TwoFingerIntent.scroll);
    expect(gesture.takeWheelSteps(), const Offset(0, 1));
    expect(gesture.update(1.2, const Offset(0, 14)), TwoFingerIntent.scroll);
    expect(gesture.takeWheelSteps(), const Offset(0, 1));
  });
  test('pinch zoom never emits scroll steps', () {
    final gesture = TwoFingerScroll();
    expect(gesture.update(1.12, const Offset(0, 8)), TwoFingerIntent.zoom);
    gesture.update(1.01, const Offset(0, 40));
    expect(gesture.takeWheelSteps(), Offset.zero);
  });
  test(
      'slow horizontal movement accumulates and direction reversal is preserved',
      () {
    final gesture = TwoFingerScroll();
    for (var i = 0; i < 16; i++) {
      gesture.update(1, const Offset(1, 0));
    }
    expect(gesture.takeWheelSteps(), const Offset(1, 0));
    gesture.update(1, const Offset(-32, 0));
    expect(gesture.takeWheelSteps(), const Offset(-2, 0));
    expect(gesture.takeWheelSteps(), Offset.zero);
  });
  test('a new gesture clears both intent and fractional movement', () {
    final gesture = TwoFingerScroll();
    gesture.update(1, const Offset(0, 15));
    gesture.reset();
    expect(gesture.intent, TwoFingerIntent.pending);
    gesture.update(0.8, const Offset(0, 1));
    expect(gesture.intent, TwoFingerIntent.zoom);
    expect(gesture.takeWheelSteps(), Offset.zero);
  });
  test('invalid deltas cannot poison later input', () {
    final gesture = TwoFingerScroll();
    gesture.update(double.nan, const Offset(0, 10));
    gesture.update(1, const Offset(double.infinity, 0));
    gesture.update(1, const Offset(0, 32));
    expect(gesture.takeWheelSteps(), const Offset(0, 2));
  });
}
