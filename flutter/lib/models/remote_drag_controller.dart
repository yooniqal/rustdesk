/// Pairs a gesture's mouse down/up, including cancellation while an async
/// cursor move is still in flight. Only the latest gesture may start a drag.
class RemoteDragController {
  RemoteDragController(this.send);
  final Future<void> Function(bool down) send;
  int _generation = 0;
  bool _pressed = false;

  Future<void> begin({Future<bool> Function()? prepare}) async {
    if (_pressed) return;
    final generation = ++_generation;
    if (prepare != null && !await prepare()) return;
    if (generation != _generation) return;
    _pressed = true;
    await send(true);
  }

  Future<void> end() async {
    ++_generation;
    if (!_pressed) return;
    _pressed = false;
    await send(false);
  }
}
