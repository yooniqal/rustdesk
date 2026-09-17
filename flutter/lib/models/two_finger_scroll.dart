import 'dart:ui';

enum TwoFingerIntent { pending, scroll, zoom }

/// Decide once per gesture, so finger jitter cannot alternate scrolling and
/// canvas zoom. Accumulate small deltas instead of losing slow movement.
class TwoFingerScroll {
  TwoFingerIntent intent = TwoFingerIntent.pending;
  Offset _pending = Offset.zero;
  int _pinchSamples = 0;

  void reset() {
    intent = TwoFingerIntent.pending;
    _pending = Offset.zero;
    _pinchSamples = 0;
  }

  TwoFingerIntent update(double scale, Offset delta) {
    if (!scale.isFinite || !delta.dx.isFinite || !delta.dy.isFinite)
      return intent;
    _pending += delta;
    if (intent == TwoFingerIntent.pending) {
      if ((scale - 1).abs() >= 0.08) {
        // Android reports the contacts separately. A parallel swipe briefly
        // changes span until the second contact's matching move arrives.
        if (++_pinchSamples >= 3) {
          intent = TwoFingerIntent.zoom;
          _pending = Offset.zero;
        }
      } else {
        _pinchSamples = 0;
        if (_pending.distance >= 12) intent = TwoFingerIntent.scroll;
      }
    }
    return intent;
  }

  Offset takeWheelSteps() {
    if (intent != TwoFingerIntent.scroll) return Offset.zero;
    const pixelsPerStep = 16.0;
    final steps = Offset((_pending.dx / pixelsPerStep).truncateToDouble(),
        (_pending.dy / pixelsPerStep).truncateToDouble());
    _pending -= steps * pixelsPerStep;
    return steps;
  }
}
