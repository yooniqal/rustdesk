import 'package:flutter/gestures.dart';

/// Route each pointer by its actual tool type, never by a preceding hover.
/// Flutter Android uses the contact ID as `device`, so a mouse and the first
/// finger can both have device=0. It is not an Android InputDevice identifier.
/// Android mouse-source events are normalized in MainActivity before Flutter.
class MobilePointerRouter {
  final Set<int> _mousePointers = {};

  bool isMouseDown(PointerDownEvent event) =>
      event.kind != PointerDeviceKind.touch;

  bool isMouseHover(PointerHoverEvent event) =>
      event.kind != PointerDeviceKind.touch;

  bool down(PointerDownEvent event) {
    final mouse = isMouseDown(event);
    if (mouse) _mousePointers.add(event.pointer);
    return mouse;
  }

  // Keep the decision for the full gesture, even when a second device starts
  // a touch gesture. Always release the matching down.
  bool isMousePointer(PointerEvent event) =>
      _mousePointers.contains(event.pointer);

  void reset() => _mousePointers.clear();

  bool end(PointerEvent event) => _mousePointers.remove(event.pointer);
}

/// Keep touch recognizers mounted when switching between mouse and fingers.
/// Filtering at pointer admission also prevents a touchpad click being sent
/// twice, once by the raw mouse listener and once by a gesture recognizer.
mixin RemotePointerFilter on GestureRecognizer {
  bool Function(PointerDownEvent)? acceptPointer;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      (acceptPointer?.call(event) ?? true) && super.isPointerAllowed(event);
}
