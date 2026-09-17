import 'dart:ui';

enum TwoFingerIntent { pending, scroll, zoom }

/// Decide once per gesture, so finger jitter cannot alternate scrolling and
/// canvas zoom. Accumulate small deltas instead of losing slow movement.
class TwoFingerScroll {
  TwoFingerIntent intent = TwoFingerIntent.pending;
  Offset _pending = Offset.zero;

  void reset() {
    intent = TwoFingerIntent.pending;
    _pending = Offset.zero;
  }

  TwoFingerIntent update(double scale, Offset delta) {
    if (!scale.isFinite || !delta.dx.isFinite || !delta.dy.isFinite)
      return intent;
    _pending += delta;
    if (intent == TwoFingerIntent.pending) {
      if ((scale - 1).abs() >= 0.08) {
        intent = TwoFingerIntent.zoom;
        _pending = Offset.zero;
      } else if (_pending.distance >= 12) {
        intent = TwoFingerIntent.scroll;
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
