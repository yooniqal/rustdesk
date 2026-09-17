typedef RemoteKeySender = void Function(String name,
    {required bool down,
    required bool press,
    required bool alt,
    required bool ctrl,
    required bool shift,
    required bool command});

/// A complete chord, independent of the keyboard toolbar's latched modifiers.
/// Linux does not expand press=true for modifier keys, so send explicit edges.
/// Releasing modifiers also dismisses the macOS application switcher.
void sendRemoteChord(RemoteKeySender send,
    {required String key,
    bool alt = false,
    bool ctrl = false,
    bool shift = false,
    bool command = false}) {
  final held = <String>[];
  void emit(String name, bool down) => send(name,
      down: down,
      press: false,
      alt: held.contains('VK_MENU'),
      ctrl: held.contains('VK_CONTROL'),
      shift: held.contains('VK_SHIFT'),
      command: held.contains('Meta'));

  for (final modifier in [
    if (ctrl) 'VK_CONTROL',
    if (alt) 'VK_MENU',
    if (shift) 'VK_SHIFT',
    if (command) 'Meta',
  ]) {
    held.add(modifier);
    emit(modifier, true);
  }
  emit(key, true);
  emit(key, false);
  while (held.isNotEmpty) {
    final modifier = held.removeLast();
    emit(modifier, false);
  }
}

void sendRemoteAppSwitch(RemoteKeySender send, {required bool isMac}) =>
    sendRemoteChord(send, key: 'VK_TAB', alt: !isMac, command: isMac);

void sendRemoteInputSource(RemoteKeySender send, {required bool isMac}) =>
    sendRemoteChord(send, key: isMac ? 'VK_SPACE' : 'VK_HANGUL', ctrl: isMac);

/// A release-only recovery command; never synthesize a modifier press here.
void sendRemoteModifierRelease(RemoteKeySender send) {
  for (final key in const [
    'VK_CONTROL',
    'RControl',
    'VK_MENU',
    'RAlt',
    'VK_SHIFT',
    'RShift',
    'Meta',
    'RWin',
  ]) {
    send(key,
        down: false,
        press: false,
        alt: false,
        ctrl: false,
        shift: false,
        command: false);
  }
}

/// Linux Legacy character input consumes the character itself, clearing Shift.
/// The toolbar's Shift must therefore be reflected in ASCII text before send.
String shiftedAscii(String text) {
  const plain = '`1234567890-=[]\\;\',./';
  const shifted = '~!@#\$%^&*()_+{}|:"<>?';
  return text.split('').map((char) {
    if (RegExp(r'^[a-z]$').hasMatch(char)) return char.toUpperCase();
    final index = plain.indexOf(char);
    return index < 0 ? char : shifted[index];
  }).join();
}
