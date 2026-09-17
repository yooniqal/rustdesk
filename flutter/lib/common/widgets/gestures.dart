import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

enum GestureState {
  none,
  oneFingerPan,
  twoFingerScale,
  threeFingerVerticalDrag
}

/// Each pointer-count change ends the old gesture before starting a new one.
/// After a multi-finger gesture, lifting one finger must not move the cursor.
class CustomTouchGestureRecognizer extends ScaleGestureRecognizer {
  CustomTouchGestureRecognizer({super.debugOwner, super.supportedDevices}) {
    onUpdate = _update;
    onEnd = _end;
  }

  GestureDragStartCallback? onOneFingerPanStart;
  GestureDragUpdateCallback? onOneFingerPanUpdate;
  GestureDragEndCallback? onOneFingerPanEnd;
  GestureDragCancelCallback? onOneFingerPanCancel;
  GestureScaleStartCallback? onTwoFingerScaleStart;
  GestureScaleUpdateCallback? onTwoFingerScaleUpdate;
  GestureScaleEndCallback? onTwoFingerScaleEnd;
  GestureDragStartCallback? onThreeFingerVerticalDragStart;
  GestureDragUpdateCallback? onThreeFingerVerticalDragUpdate;
  GestureDragEndCallback? onThreeFingerVerticalDragEnd;

  GestureState _currentState = GestureState.none;
  PointerDeviceKind? _kind;
  PointerDeviceKind? get pointerKind => _kind;
  int _minimumPointers = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _kind = event.kind;
    super.addAllowedPointer(event);
  }

  void _update(ScaleUpdateDetails d) {
    if (d.pointerCount < _minimumPointers) return;
    _minimumPointers = d.pointerCount;
    final next = switch (d.pointerCount) {
      1 => GestureState.oneFingerPan,
      2 => GestureState.twoFingerScale,
      3 => GestureState.threeFingerVerticalDrag,
      _ => GestureState.none,
    };
    if (next != _currentState) {
      _end(ScaleEndDetails(pointerCount: d.pointerCount));
      _currentState = next;
      final start = DragStartDetails(
          kind: _kind,
          globalPosition: d.focalPoint,
          localPosition: d.localFocalPoint);
      switch (next) {
        case GestureState.oneFingerPan:
          onOneFingerPanStart?.call(start);
          break;
        case GestureState.twoFingerScale:
          onTwoFingerScaleStart?.call(ScaleStartDetails(
              focalPoint: d.focalPoint,
              localFocalPoint: d.localFocalPoint,
              pointerCount: d.pointerCount));
          break;
        case GestureState.threeFingerVerticalDrag:
          onThreeFingerVerticalDragStart?.call(start);
          break;
        case GestureState.none:
          break;
      }
    }
    final drag = DragUpdateDetails(
        globalPosition: d.focalPoint,
        localPosition: d.localFocalPoint,
        delta: d.focalPointDelta);
    switch (_currentState) {
      case GestureState.oneFingerPan:
        onOneFingerPanUpdate?.call(drag);
        break;
      case GestureState.twoFingerScale:
        onTwoFingerScaleUpdate?.call(d);
        break;
      case GestureState.threeFingerVerticalDrag:
        onThreeFingerVerticalDragUpdate?.call(drag);
        break;
      case GestureState.none:
        break;
    }
  }

  void _end(ScaleEndDetails d) {
    final previous = _currentState;
    _currentState = GestureState.none;
    if (d.pointerCount == 0) _minimumPointers = 0;
    switch (previous) {
      case GestureState.oneFingerPan:
        onOneFingerPanEnd?.call(DragEndDetails(velocity: d.velocity));
        break;
      case GestureState.twoFingerScale:
        onTwoFingerScaleEnd?.call(d);
        break;
      case GestureState.threeFingerVerticalDrag:
        onThreeFingerVerticalDragEnd
            ?.call(DragEndDetails(velocity: d.velocity));
        break;
      case GestureState.none:
        break;
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    _end(ScaleEndDetails());
  }

  @override
  void rejectGesture(int pointer) {
    if (_currentState == GestureState.oneFingerPan) {
      _currentState = GestureState.none;
      onOneFingerPanCancel?.call();
    } else {
      _end(ScaleEndDetails());
    }
    super.rejectGesture(pointer);
  }

  @override
  void dispose() {
    _end(ScaleEndDetails());
    super.dispose();
  }
}

/// Tap, then hold or move the second tap to drag. Every arena hold is paired
/// with a release, including cancellation and disposal.
class HoldTapMoveGestureRecognizer extends GestureRecognizer {
  HoldTapMoveGestureRecognizer({super.debugOwner, super.supportedDevices});

  GestureDragStartCallback? onHoldDragStart;
  GestureDragUpdateCallback? onHoldDragUpdate;
  GestureDragDownCallback? onHoldDragDown;
  GestureDragCancelCallback? onHoldDragCancel;
  GestureDragEndCallback? onHoldDragEnd;

  _TapTracker? _first;
  _TapTracker? _second;
  PointerDownEvent? _secondDown;
  bool _firstUp = false;
  bool _dragging = false;
  Timer? _timer;
  final Set<int> _heldArenas = {};

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      event.buttons == kPrimaryButton &&
      (onHoldDragStart != null || onHoldDragUpdate != null) &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_first != null &&
        (!_firstUp ||
            _second != null ||
            !_first!.isWithinGlobalTolerance(event, kDoubleTapSlop) ||
            !_first!.hasElapsedMinTime() ||
            !_first!.hasSameButton(event))) {
      _finish();
      // A simultaneous second finger belongs to the two-finger recognizer.
      return;
    }
    final tracker = _TapTracker(
        event: event,
        entry: GestureBinding.instance.gestureArena.add(event.pointer, this),
        doubleTapMinTime: kDoubleTapMinTime,
        gestureSettings: gestureSettings);
    if (_first == null) {
      _first = tracker;
    } else {
      _timer?.cancel();
      _second = tracker;
      _secondDown = event;
      onHoldDragDown?.call(DragDownDetails(
          globalPosition: event.position, localPosition: event.localPosition));
      _timer = Timer(kDoubleTapTimeout, _startDrag);
    }
    tracker.startTrackingPointer(_handleEvent, event.transform);
  }

  void _handleEvent(PointerEvent event) {
    final second = _second;
    if (event is PointerCancelEvent) {
      _finish();
    } else if (event is PointerUpEvent) {
      if (event.pointer == _first?.pointer && !_firstUp) {
        _firstUp = true;
        _first!.stopTrackingPointer(_handleEvent);
        GestureBinding.instance.gestureArena.hold(event.pointer);
        _heldArenas.add(event.pointer);
        _timer = Timer(kDoubleTapTimeout, _finish);
      } else if (event.pointer == second?.pointer) {
        final wasDragging = _dragging;
        _finish(completed: wasDragging);
        if (wasDragging) onHoldDragEnd?.call(DragEndDetails());
      }
    } else if (event is PointerMoveEvent) {
      if (event.pointer == second?.pointer) {
        if (!_dragging && !second!.isWithinGlobalTolerance(event, kTouchSlop)) {
          _startDrag();
        }
        if (_dragging) {
          onHoldDragUpdate?.call(DragUpdateDetails(
              globalPosition: event.position,
              localPosition: event.localPosition,
              delta: event.delta));
        }
      } else if (_first != null &&
          !_first!.isWithinGlobalTolerance(event, kTouchSlop)) {
        _finish();
      }
    }
  }

  void _startDrag() {
    if (_dragging || _second == null) return;
    _timer?.cancel();
    _dragging = true;
    _first?.entry.resolve(GestureDisposition.accepted);
    _second?.entry.resolve(GestureDisposition.accepted);
    _releaseArenas();
    final event = _secondDown!;
    onHoldDragStart?.call(DragStartDetails(
        kind: event.kind,
        globalPosition: event.position,
        localPosition: event.localPosition));
  }

  void _releaseArenas() {
    final held = _heldArenas.toList();
    _heldArenas.clear();
    for (final pointer in held) {
      GestureBinding.instance.gestureArena.release(pointer);
    }
  }

  void _finish({bool completed = false}) {
    _timer?.cancel();
    _timer = null;
    final trackers = [_first, _second].whereType<_TapTracker>().toList();
    final wasDragging = _dragging;
    _first = _second = null;
    _secondDown = null;
    _firstUp = _dragging = false;
    for (final tracker in trackers) {
      tracker.stopTrackingPointer(_handleEvent);
      if (!wasDragging) tracker.entry.resolve(GestureDisposition.rejected);
    }
    _releaseArenas();
    if (wasDragging && !completed) onHoldDragCancel?.call();
  }

  @override
  void acceptGesture(int pointer) {}
  @override
  void rejectGesture(int pointer) {
    if (pointer == _first?.pointer || pointer == _second?.pointer) _finish();
  }

  @override
  void dispose() {
    _finish();
    super.dispose();
  }

  @override
  String get debugDescription => 'tap then hold to drag';
}

/// Exactly two overlapping contacts form a right-click. Sequential taps,
/// movement, a third finger, timeout and cancellation all reject the gesture.
class DoubleFinerTapGestureRecognizer extends GestureRecognizer {
  DoubleFinerTapGestureRecognizer({super.debugOwner, super.supportedDevices});
  GestureTapDownCallback? onDoubleFinerTapDown;
  GestureTapDownCallback? onDoubleFinerTap;
  GestureTapCancelCallback? onDoubleFinerTapCancel;
  final Map<int, _TapTracker> _trackers = {};
  final Set<int> _up = {};
  Timer? _timer;
  PointerDownEvent? _firstDown;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      event.buttons == kPrimaryButton &&
      onDoubleFinerTap != null &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_trackers.length >= 2 || _up.isNotEmpty) {
      _finish();
      return;
    }
    _firstDown ??= event;
    final tracker = _TapTracker(
        event: event,
        entry: GestureBinding.instance.gestureArena.add(event.pointer, this),
        doubleTapMinTime: kDoubleTapMinTime,
        gestureSettings: gestureSettings);
    _trackers[event.pointer] = tracker;
    GestureBinding.instance.gestureArena.hold(event.pointer);
    tracker.startTrackingPointer(_handleEvent, event.transform);
    _timer ??= Timer(kDoubleTapTimeout, _finish);
    if (_trackers.length == 2) {
      onDoubleFinerTapDown?.call(TapDownDetails(
          kind: event.kind,
          globalPosition: event.position,
          localPosition: event.localPosition));
    }
  }

  void _handleEvent(PointerEvent event) {
    final tracker = _trackers[event.pointer];
    if (tracker == null) return;
    if (event is PointerCancelEvent ||
        (event is PointerMoveEvent &&
            !tracker.isWithinGlobalTolerance(event, kTouchSlop))) {
      _finish();
    } else if (event is PointerUpEvent) {
      _up.add(event.pointer);
      if (_trackers.length != 2) {
        _finish();
      } else if (_up.length == 2) {
        _finish(accepted: true);
      }
    }
  }

  void _finish({bool accepted = false}) {
    _timer?.cancel();
    _timer = null;
    final trackers = _trackers.values.toList();
    final first = _firstDown;
    _trackers.clear();
    _up.clear();
    _firstDown = null;
    for (final tracker in trackers) {
      tracker.stopTrackingPointer(_handleEvent);
      tracker.entry.resolve(
          accepted ? GestureDisposition.accepted : GestureDisposition.rejected);
    }
    for (final tracker in trackers) {
      GestureBinding.instance.gestureArena.release(tracker.pointer);
    }
    if (accepted && first != null) {
      onDoubleFinerTap?.call(TapDownDetails(
          kind: first.kind,
          globalPosition: first.position,
          localPosition: first.localPosition));
    } else if (trackers.isNotEmpty) {
      onDoubleFinerTapCancel?.call();
    }
  }

  @override
  void acceptGesture(int pointer) {}
  @override
  void rejectGesture(int pointer) {
    if (_trackers.containsKey(pointer)) _finish();
  }

  @override
  void dispose() {
    _finish();
    super.dispose();
  }

  @override
  String get debugDescription => 'two finger tap';
}

/// TapTracker helps track individual tap sequences as part of a
/// larger gesture.
class _TapTracker {
  _TapTracker({
    required PointerDownEvent event,
    required this.entry,
    required Duration doubleTapMinTime,
    required this.gestureSettings,
  })  : pointer = event.pointer,
        _initialGlobalPosition = event.position,
        initialButtons = event.buttons,
        _doubleTapMinTimeCountdown =
            _CountdownZoned(duration: doubleTapMinTime);

  final DeviceGestureSettings? gestureSettings;
  final int pointer;
  final GestureArenaEntry entry;
  final Offset _initialGlobalPosition;
  final int initialButtons;
  final _CountdownZoned _doubleTapMinTimeCountdown;

  bool _isTrackingPointer = false;

  void startTrackingPointer(PointerRoute route, Matrix4? transform) {
    if (!_isTrackingPointer) {
      _isTrackingPointer = true;
      GestureBinding.instance.pointerRouter.addRoute(pointer, route, transform);
    }
  }

  void stopTrackingPointer(PointerRoute route) {
    if (_isTrackingPointer) {
      _isTrackingPointer = false;
      GestureBinding.instance.pointerRouter.removeRoute(pointer, route);
    }
  }

  bool isWithinGlobalTolerance(PointerEvent event, double tolerance) {
    final Offset offset = event.position - _initialGlobalPosition;
    return offset.distance <= tolerance;
  }

  bool hasElapsedMinTime() {
    return _doubleTapMinTimeCountdown.timeout;
  }

  bool hasSameButton(PointerDownEvent event) {
    return event.buttons == initialButtons;
  }
}

/// CountdownZoned tracks whether the specified duration has elapsed since
/// creation, honoring [Zone].
class _CountdownZoned {
  _CountdownZoned({required Duration duration}) {
    Timer(duration, _onTimeout);
  }

  bool _timeout = false;

  bool get timeout => _timeout;

  void _onTimeout() {
    _timeout = true;
  }
}

RawGestureDetector getMixinGestureDetector({
  Widget? child,
  GestureTapUpCallback? onTapUp,
  GestureTapDownCallback? onDoubleTapDown,
  GestureDoubleTapCallback? onDoubleTap,
  GestureLongPressDownCallback? onLongPressDown,
  GestureLongPressCallback? onLongPress,
  GestureDragStartCallback? onHoldDragStart,
  GestureDragUpdateCallback? onHoldDragUpdate,
  GestureDragCancelCallback? onHoldDragCancel,
  GestureDragEndCallback? onHoldDragEnd,
  GestureTapDownCallback? onDoubleFinerTap,
  GestureDragStartCallback? onOneFingerPanStart,
  GestureDragUpdateCallback? onOneFingerPanUpdate,
  GestureDragEndCallback? onOneFingerPanEnd,
  GestureDragCancelCallback? onOneFingerPanCancel,
  GestureScaleUpdateCallback? onTwoFingerScaleUpdate,
  GestureScaleEndCallback? onTwoFingerScaleEnd,
  GestureDragUpdateCallback? onThreeFingerVerticalDragUpdate,
}) {
  return RawGestureDetector(
      child: child,
      gestures: <Type, GestureRecognizerFactory>{
        // Official
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                () => TapGestureRecognizer(), (instance) {
          instance.onTapUp = onTapUp;
        }),
        DoubleTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
                () => DoubleTapGestureRecognizer(), (instance) {
          instance
            ..onDoubleTapDown = onDoubleTapDown
            ..onDoubleTap = onDoubleTap;
        }),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(), (instance) {
          instance
            ..onLongPressDown = onLongPressDown
            ..onLongPress = onLongPress;
        }),
        // Customized
        HoldTapMoveGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<HoldTapMoveGestureRecognizer>(
                () => HoldTapMoveGestureRecognizer(),
                (instance) => instance
                  ..onHoldDragStart = onHoldDragStart
                  ..onHoldDragUpdate = onHoldDragUpdate
                  ..onHoldDragCancel = onHoldDragCancel
                  ..onHoldDragEnd = onHoldDragEnd),
        DoubleFinerTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                DoubleFinerTapGestureRecognizer>(
            () => DoubleFinerTapGestureRecognizer(), (instance) {
          instance.onDoubleFinerTap = onDoubleFinerTap;
        }),
        CustomTouchGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<CustomTouchGestureRecognizer>(
                () => CustomTouchGestureRecognizer(), (instance) {
          instance
            ..onOneFingerPanStart = onOneFingerPanStart
            ..onOneFingerPanUpdate = onOneFingerPanUpdate
            ..onOneFingerPanEnd = onOneFingerPanEnd
            ..onOneFingerPanCancel = onOneFingerPanCancel
            ..onTwoFingerScaleUpdate = onTwoFingerScaleUpdate
            ..onTwoFingerScaleEnd = onTwoFingerScaleEnd
            ..onThreeFingerVerticalDragUpdate = onThreeFingerVerticalDragUpdate;
        }),
      });
}
