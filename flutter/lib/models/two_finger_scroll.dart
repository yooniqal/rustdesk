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

  // 2026-10-29 "휠 하려는데 화면이 줌되면서 포커스가 움직인다": 손가락이 조금만 벌어져도(8%)
  // 줌으로 굳었다. 이제 평행 이동이 먼저 쌓이면 휠로 정하고, 줌은 크게(18%↑) 벌리거나 오므린
  // 상태가 연속으로 이어질 때만. 순수 핀치는 두 손가락이 반대로 움직여 초점 이동이 작다.
  static const _scrollDistance = 14.0;
  static const _zoomScale = 0.18;

  TwoFingerIntent update(double scale, Offset delta) {
    if (!scale.isFinite || !delta.dx.isFinite || !delta.dy.isFinite)
      return intent;
    _pending += delta;
    if (intent == TwoFingerIntent.pending) {
      if (_pending.distance >= _scrollDistance) {
        intent = TwoFingerIntent.scroll;
      } else if ((scale - 1).abs() >= _zoomScale) {
        // Android reports the contacts separately. A parallel swipe briefly
        // changes span until the second contact's matching move arrives.
        if (++_pinchSamples >= 3) {
          intent = TwoFingerIntent.zoom;
          _pending = Offset.zero;
        }
      } else {
        _pinchSamples = 0;
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
