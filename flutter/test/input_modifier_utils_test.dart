import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/input_modifier_utils.dart';

void main() {
  test('logical Hangul wins over the shared Right Alt physical position', () {
    expect(
        isKoreanInputToggle(
            LogicalKeyboardKey.hangulMode, PhysicalKeyboardKey.altRight),
        isTrue);
  });
  test('dedicated physical language key is supported', () {
    expect(
        isKoreanInputToggle(
            LogicalKeyboardKey.lang1, PhysicalKeyboardKey.lang1),
        isTrue);
  });
  test('ordinary Right Alt remains available for shortcuts', () {
    expect(
        isKoreanInputToggle(
            LogicalKeyboardKey.altRight, PhysicalKeyboardKey.altRight),
        isFalse);
  });
  group('shouldReleaseStaleMobileShift', () {
    test('does not release when cached shift is already false', () {
      expect(
        shouldReleaseStaleMobileShift(
          isMobile: true,
          cachedShiftPressed: false,
          actualShiftPressed: false,
          logicalKey: LogicalKeyboardKey.keyD,
          hasTrackedShiftKeyDown: true,
        ),
        isFalse,
      );
    });

    test('releases one-shot mobile shift after a text key', () {
      expect(
        shouldReleaseStaleMobileShift(
          isMobile: true,
          cachedShiftPressed: true,
          actualShiftPressed: false,
          logicalKey: LogicalKeyboardKey.keyD,
          hasTrackedShiftKeyDown: true,
        ),
        isTrue,
      );
    });

    test('does not release manually toggled shift without tracked key down',
        () {
      expect(
        shouldReleaseStaleMobileShift(
          isMobile: true,
          cachedShiftPressed: true,
          actualShiftPressed: false,
          logicalKey: LogicalKeyboardKey.keyD,
          hasTrackedShiftKeyDown: false,
        ),
        isFalse,
      );
    });

    test('does not release when shift is still physically pressed', () {
      expect(
        shouldReleaseStaleMobileShift(
          isMobile: true,
          cachedShiftPressed: true,
          actualShiftPressed: true,
          logicalKey: LogicalKeyboardKey.keyD,
          hasTrackedShiftKeyDown: true,
        ),
        isFalse,
      );
    });

    test('does not release on non-mobile platforms', () {
      expect(
        shouldReleaseStaleMobileShift(
          isMobile: false,
          cachedShiftPressed: true,
          actualShiftPressed: false,
          logicalKey: LogicalKeyboardKey.keyD,
          hasTrackedShiftKeyDown: true,
        ),
        isFalse,
      );
    });

    test('releases on enter key', () {
      expect(
        shouldReleaseStaleMobileShift(
          isMobile: true,
          cachedShiftPressed: true,
          actualShiftPressed: false,
          logicalKey: LogicalKeyboardKey.enter,
          hasTrackedShiftKeyDown: true,
        ),
        isTrue,
      );
    });

    test('releases on arrow key', () {
      expect(
        shouldReleaseStaleMobileShift(
          isMobile: true,
          cachedShiftPressed: true,
          actualShiftPressed: false,
          logicalKey: LogicalKeyboardKey.arrowLeft,
          hasTrackedShiftKeyDown: true,
        ),
        isTrue,
      );
    });

    test('does not release on modifier events', () {
      expect(
        shouldReleaseStaleMobileShift(
          isMobile: true,
          cachedShiftPressed: true,
          actualShiftPressed: false,
          logicalKey: LogicalKeyboardKey.shiftLeft,
          hasTrackedShiftKeyDown: true,
        ),
        isFalse,
      );
    });

    test('does not release on shiftRight modifier events', () {
      expect(
        shouldReleaseStaleMobileShift(
          isMobile: true,
          cachedShiftPressed: true,
          actualShiftPressed: false,
          logicalKey: LogicalKeyboardKey.shiftRight,
          hasTrackedShiftKeyDown: true,
        ),
        isFalse,
      );
    });
  });
}
