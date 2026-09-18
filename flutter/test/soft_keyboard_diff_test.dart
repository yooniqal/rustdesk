import 'package:flutter_test/flutter_test.dart';

import '../lib/models/soft_keyboard_diff.dart';

final s = '1' * 1024;

// 입력창 값의 연속을 원격 문서에 적용했을 때의 결과.
String replay(List<String> values) {
  var remote = <int>[];
  var old = values.first;
  for (final value in values.skip(1)) {
    final edit = diffSoftKeyboardText(old, value);
    expect(edit.backspaces <= remote.length, isTrue,
        reason: 'would delete text typed before this session');
    remote = remote.sublist(0, remote.length - edit.backspaces)
      ..addAll(edit.inserted.runes);
    old = value;
  }
  return String.fromCharCodes(remote);
}

void main() {
  test('sends each letter of a word that stays in composing state', () {
    // 삼성 키보드: 스페이스 전까지 단어 전체가 조합 상태. 글자마다 바로 나가야 한다.
    final h = diffSoftKeyboardText(s, '${s}h');
    expect(h.backspaces, 0);
    expect(h.inserted, 'h');
    final e = diffSoftKeyboardText('${s}h', '${s}he');
    expect(e.backspaces, 0);
    expect(e.inserted, 'e');
    expect(replay([s, '${s}h', '${s}he', '${s}hel', '${s}hell', '${s}hello ']),
        'hello ');
  });

  test('composes hangul syllables by replacing the last character', () {
    final edit = diffSoftKeyboardText('${s}ㄱ', '${s}가');
    expect(edit.backspaces, 1);
    expect(edit.inserted, '가');
    expect(
        replay([s, '${s}ㄱ', '${s}가', '${s}각', '${s}가구', '${s}가굿', '${s}가구사']),
        '가구사');
  });

  test('never sends the sentinel when the cursor is not at the end', () {
    // 예전 증상: 무엇을 쳐도 1 이 전송됨.
    for (final value in ['h$s', '${'1' * 500}h${'1' * 524}']) {
      final edit = diffSoftKeyboardText(s, value);
      expect(edit.backspaces, 0);
      expect(edit.inserted, 'h');
      expect(edit.resync, isTrue);
    }
  });

  test('typing the digit 1 sends exactly one 1', () {
    final edit = diffSoftKeyboardText(s, '${s}1');
    expect(edit.backspaces, 0);
    expect(edit.inserted, '1');
    expect(edit.resync, isFalse);
    expect(replay([s, '${s}1', '${s}11', '${s}11a']), '11a');
  });

  test('backspace on typed text and on the bare sentinel', () {
    expect(diffSoftKeyboardText('${s}ab', '${s}a').backspaces, 1);
    final edit = diffSoftKeyboardText(s, '1' * 1023);
    expect(edit.backspaces, 1);
    expect(edit.inserted, '');
  });

  test('retypes the tail when a word is corrected in the middle', () {
    final edit = diffSoftKeyboardText('${s}helo', '${s}hello');
    expect(edit.backspaces, 1);
    expect(edit.inserted, 'lo');
    expect(replay([s, '${s}teh', '${s}the ']), 'the ');
  });

  test('counts an emoji as one backspace and does not split it', () {
    expect(diffSoftKeyboardText('$s😀', s).backspaces, 1);
    final edit = diffSoftKeyboardText('$s😀', '$s😁');
    expect(edit.backspaces, 1);
    expect(edit.inserted, '😁');
  });

  test('gives up instead of wiping the remote document', () {
    for (final value in ['', 'abc', '${'1' * 900}x']) {
      final edit = diffSoftKeyboardText(s, value);
      expect(edit.isEmpty, isTrue);
      expect(edit.resync, isTrue);
    }
    final pasted = diffSoftKeyboardText(s, s + 'a' * 1000);
    expect(pasted.isEmpty, isTrue);
    expect(pasted.resync, isTrue);
  });

  test('no change sends nothing', () {
    final edit = diffSoftKeyboardText(s, s);
    expect(edit.isEmpty, isTrue);
    expect(edit.resync, isFalse);
  });
}
