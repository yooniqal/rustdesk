import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/remote_shortcuts.dart';

class Recorder {
  final events = <Map<String, Object>>[];
  void send(String name,
          {required bool down,
          required bool press,
          required bool alt,
          required bool ctrl,
          required bool shift,
          required bool command}) =>
      events.add({
        'name': name,
        'down': down,
        'press': press,
        'alt': alt,
        'ctrl': ctrl,
        'shift': shift,
        'command': command,
      });
  List<String> get edges => events
      .map((e) => '${e['name']}:${e['down'] == true ? 'down' : 'up'}')
      .toList();
}

void main() {
  test('Windows/Linux app switch sends and releases Alt+Tab', () {
    final recorder = Recorder();
    sendRemoteAppSwitch(recorder.send, isMac: false);
    expect(recorder.edges,
        ['VK_MENU:down', 'VK_TAB:down', 'VK_TAB:up', 'VK_MENU:up']);
    expect(recorder.events[1]['alt'], isTrue);
    expect(recorder.events.last['alt'], isFalse);
    expect(recorder.events.every((e) => e['press'] == false), isTrue);
  });
  test('macOS app switch uses Command and releases it', () {
    final recorder = Recorder();
    sendRemoteAppSwitch(recorder.send, isMac: true);
    expect(
        recorder.edges, ['Meta:down', 'VK_TAB:down', 'VK_TAB:up', 'Meta:up']);
    expect(recorder.events[1]['command'], isTrue);
    expect(recorder.events[1]['alt'], isFalse);
    expect(recorder.events.last['command'], isFalse);
  });
  test('input source uses Hangul on PC and Ctrl+Space on Mac', () {
    final pc = Recorder(), mac = Recorder();
    sendRemoteInputSource(pc.send, isMac: false);
    sendRemoteInputSource(mac.send, isMac: true);
    expect(pc.edges, ['VK_HANGUL:down', 'VK_HANGUL:up']);
    expect(mac.edges,
        ['VK_CONTROL:down', 'VK_SPACE:down', 'VK_SPACE:up', 'VK_CONTROL:up']);
  });
  test('standalone Super has explicit down/up for Linux', () {
    final recorder = Recorder();
    sendRemoteChord(recorder.send, key: 'Meta');
    expect(recorder.edges, ['Meta:down', 'Meta:up']);
  });
  test(
      'Shift+Tab and Ctrl+Shift shortcuts preserve the chord and release in reverse',
      () {
    final recorder = Recorder();
    sendRemoteChord(recorder.send, key: 'VK_TAB', ctrl: true, shift: true);
    expect(recorder.edges, [
      'VK_CONTROL:down',
      'VK_SHIFT:down',
      'VK_TAB:down',
      'VK_TAB:up',
      'VK_SHIFT:up',
      'VK_CONTROL:up'
    ]);
    expect(recorder.events[2]['ctrl'], isTrue);
    expect(recorder.events[2]['shift'], isTrue);
    expect(recorder.events[4]['shift'], isFalse);
    expect(recorder.events[4]['ctrl'], isTrue);
  });
  test('shortcut key names exist in the Rust protocol map', () {
    final map = File('../src/client.rs').readAsStringSync();
    final recorder = Recorder();
    sendRemoteChord(recorder.send,
        key: 'VK_TAB', ctrl: true, alt: true, shift: true, command: true);
    sendRemoteInputSource(recorder.send, isMac: false);
    sendRemoteInputSource(recorder.send, isMac: true);
    for (final event in recorder.events) {
      expect(map, contains('("${event['name']}", Key::'),
          reason: '${event['name']}');
    }
  });
  test(
      'Linux Shift text covers ASCII letters and punctuation without corrupting Korean',
      () {
    expect(shiftedAscii('abc123-=[]\\;\',./`'), 'ABC!@#_+{}|:"<>?~');
    expect(shiftedAscii('ABC! 한글'), 'ABC! 한글');
  });
}
