import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/raw_key_tracker.dart';

RawKeyDownEvent down(int code, int modifiers) => RawKeyDownEvent(
    data: RawKeyEventDataAndroid(
        keyCode: code,
        scanCode: 0,
        metaState: modifiers,
        flags: 0,
        codePoint: 0,
        plainCodePoint: 0));
RawKeyUpEvent up(int code, int modifiers) => RawKeyUpEvent(
    data: RawKeyEventDataAndroid(
        keyCode: code,
        scanCode: 0,
        metaState: modifiers,
        flags: 0,
        codePoint: 0,
        plainCodePoint: 0));

void main() {
  test('Alt+Ctrl+Shift tracks every key even when Alt is already held', () {
    final tracker = ToReleaseRawKeys();
    final alt = down(57, 2), ctrl = down(113, 0x1002), shift = down(59, 0x1003);
    tracker.updateKeyDown(LogicalKeyboardKey.altLeft, alt);
    tracker.updateKeyDown(LogicalKeyboardKey.controlLeft, ctrl);
    tracker.updateKeyDown(LogicalKeyboardKey.shiftLeft, shift);
    expect(tracker.lastLAltKeyEvent, same(alt));
    expect(tracker.lastLCtrlKeyEvent, same(ctrl));
    expect(tracker.lastLShiftKeyEvent, same(shift));
  });
  test('key up clears tracking when its modifier flag is already off', () {
    final tracker = ToReleaseRawKeys();
    tracker.updateKeyDown(LogicalKeyboardKey.shiftLeft, down(59, 1));
    tracker.updateKeyUp(LogicalKeyboardKey.shiftLeft, up(59, 0));
    expect(tracker.lastLShiftKeyEvent, isNull);
  });
  test('releasing Ctrl with Alt held keeps only Alt tracked', () {
    final tracker = ToReleaseRawKeys();
    tracker.updateKeyDown(LogicalKeyboardKey.altLeft, down(57, 2));
    tracker.updateKeyDown(LogicalKeyboardKey.controlLeft, down(113, 0x1002));
    tracker.updateKeyUp(LogicalKeyboardKey.controlLeft, up(113, 2));
    expect(tracker.lastLCtrlKeyEvent, isNull);
    expect(tracker.lastLAltKeyEvent, isNotNull);
  });
  test('left and right modifiers are independent', () {
    final tracker = ToReleaseRawKeys();
    tracker.updateKeyDown(LogicalKeyboardKey.altLeft, down(57, 2));
    tracker.updateKeyDown(LogicalKeyboardKey.altRight, down(58, 2));
    tracker.updateKeyUp(LogicalKeyboardKey.altRight, up(58, 2));
    expect(tracker.lastRAltKeyEvent, isNull);
    expect(tracker.lastLAltKeyEvent, isNotNull);
  });
  test('focus loss releases all held modifiers exactly once', () {
    final tracker = ToReleaseRawKeys();
    tracker.updateKeyDown(LogicalKeyboardKey.altLeft, down(57, 2));
    tracker.updateKeyDown(LogicalKeyboardKey.shiftRight, down(60, 3));
    tracker.updateKeyDown(LogicalKeyboardKey.metaLeft, down(117, 0x10003));
    final released = <RawKeyEvent>[];
    KeyEventResult release(RawKeyEvent event) {
      released.add(event);
      return KeyEventResult.handled;
    }

    tracker.release(release);
    tracker.release(release);
    expect(released, hasLength(3));
    expect(released.every((event) => event is RawKeyUpEvent), isTrue);
    expect(
        released.map((event) => (event.data as RawKeyEventDataAndroid).keyCode),
        unorderedEquals([57, 60, 117]));
  });
}
