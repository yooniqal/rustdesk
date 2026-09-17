import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class ToReleaseRawKeys {
  RawKeyEvent? lastLShiftKeyEvent;
  RawKeyEvent? lastRShiftKeyEvent;
  RawKeyEvent? lastLCtrlKeyEvent;
  RawKeyEvent? lastRCtrlKeyEvent;
  RawKeyEvent? lastLAltKeyEvent;
  RawKeyEvent? lastRAltKeyEvent;
  RawKeyEvent? lastLCommandKeyEvent;
  RawKeyEvent? lastRCommandKeyEvent;
  RawKeyEvent? lastSuperKeyEvent;

  reset() {
    lastLShiftKeyEvent = null;
    lastRShiftKeyEvent = null;
    lastLCtrlKeyEvent = null;
    lastRCtrlKeyEvent = null;
    lastLAltKeyEvent = null;
    lastRAltKeyEvent = null;
    lastLCommandKeyEvent = null;
    lastRCommandKeyEvent = null;
    lastSuperKeyEvent = null;
  }

  // Track the changed key, not the aggregate modifier flags. Key-up flags
  // already exclude the released key, and multiple modifiers may be held.
  void updateKeyDown(LogicalKeyboardKey logicKey, RawKeyDownEvent e) {
    if (logicKey == LogicalKeyboardKey.altLeft) {
      lastLAltKeyEvent = e;
    } else if (logicKey == LogicalKeyboardKey.altRight) {
      lastRAltKeyEvent = e;
    } else if (logicKey == LogicalKeyboardKey.controlLeft) {
      lastLCtrlKeyEvent = e;
    } else if (logicKey == LogicalKeyboardKey.controlRight) {
      lastRCtrlKeyEvent = e;
    } else if (logicKey == LogicalKeyboardKey.shiftLeft) {
      lastLShiftKeyEvent = e;
    } else if (logicKey == LogicalKeyboardKey.shiftRight) {
      lastRShiftKeyEvent = e;
    } else if (logicKey == LogicalKeyboardKey.metaLeft) {
      lastLCommandKeyEvent = e;
    } else if (logicKey == LogicalKeyboardKey.metaRight) {
      lastRCommandKeyEvent = e;
    } else if (logicKey == LogicalKeyboardKey.superKey) {
      lastSuperKeyEvent = e;
    }
  }

  void updateKeyUp(LogicalKeyboardKey logicKey, RawKeyUpEvent e) {
    if (logicKey == LogicalKeyboardKey.altLeft) {
      lastLAltKeyEvent = null;
    } else if (logicKey == LogicalKeyboardKey.altRight) {
      lastRAltKeyEvent = null;
    } else if (logicKey == LogicalKeyboardKey.controlLeft) {
      lastLCtrlKeyEvent = null;
    } else if (logicKey == LogicalKeyboardKey.controlRight) {
      lastRCtrlKeyEvent = null;
    } else if (logicKey == LogicalKeyboardKey.shiftLeft) {
      lastLShiftKeyEvent = null;
    } else if (logicKey == LogicalKeyboardKey.shiftRight) {
      lastRShiftKeyEvent = null;
    } else if (logicKey == LogicalKeyboardKey.metaLeft) {
      lastLCommandKeyEvent = null;
    } else if (logicKey == LogicalKeyboardKey.metaRight) {
      lastRCommandKeyEvent = null;
    } else if (logicKey == LogicalKeyboardKey.superKey) {
      lastSuperKeyEvent = null;
    }
  }

  release(KeyEventResult Function(RawKeyEvent e) handleRawKeyEvent) {
    for (final key in [
      lastLShiftKeyEvent,
      lastRShiftKeyEvent,
      lastLCtrlKeyEvent,
      lastRCtrlKeyEvent,
      lastLAltKeyEvent,
      lastRAltKeyEvent,
      lastLCommandKeyEvent,
      lastRCommandKeyEvent,
      lastSuperKeyEvent,
    ]) {
      if (key != null) {
        handleRawKeyEvent(RawKeyUpEvent(
          data: key.data,
          character: key.character,
        ));
      }
    }
    reset();
  }
}
