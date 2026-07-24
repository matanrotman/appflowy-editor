import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

KeyDownEvent _event({
  required LogicalKeyboardKey logical,
  required PhysicalKeyboardKey physical,
}) =>
    KeyDownEvent(
      logicalKey: logical,
      physicalKey: physical,
      timeStamp: Duration.zero,
    );

void main() async {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('keybinding_test.dart', () {
    test('keybinding parse(cmd+shift+alt+ctrl+a)', () {
      const command = 'cmd+shift+alt+ctrl+a';
      final keybinding = Keybinding.parse(command);
      expect(keybinding.isAltPressed, true);
      expect(keybinding.isShiftPressed, true);
      expect(keybinding.isMetaPressed, true);
      expect(keybinding.isControlPressed, true);
      expect(keybinding.keyLabel, 'a');
    });

    test('keybinding parse(cmd+shift+alt+a)', () {
      const command = 'cmd+shift+alt+a';
      final keybinding = Keybinding.parse(command);
      expect(keybinding.isAltPressed, true);
      expect(keybinding.isShiftPressed, true);
      expect(keybinding.isMetaPressed, true);
      expect(keybinding.isControlPressed, false);
      expect(keybinding.keyLabel, 'a');
    });

    test('keybinding parse(cmd+shift+ctrl+a)', () {
      const command = 'cmd+shift+ctrl+a';
      final keybinding = Keybinding.parse(command);
      expect(keybinding.isAltPressed, false);
      expect(keybinding.isShiftPressed, true);
      expect(keybinding.isMetaPressed, true);
      expect(keybinding.isControlPressed, true);
      expect(keybinding.keyLabel, 'a');
    });

    test('keybinding parse(cmd+alt+ctrl+a)', () {
      const command = 'cmd+alt+ctrl+a';
      final keybinding = Keybinding.parse(command);
      expect(keybinding.isAltPressed, true);
      expect(keybinding.isShiftPressed, false);
      expect(keybinding.isMetaPressed, true);
      expect(keybinding.isControlPressed, true);
      expect(keybinding.keyLabel, 'a');
    });

    test('keybinding parse(shift+alt+ctrl+a)', () {
      const command = 'shift+alt+ctrl+a';
      final keybinding = Keybinding.parse(command);
      expect(keybinding.isAltPressed, true);
      expect(keybinding.isShiftPressed, true);
      expect(keybinding.isMetaPressed, false);
      expect(keybinding.isControlPressed, true);
      expect(keybinding.keyLabel, 'a');
    });

    test('keybinding copyWith', () {
      const command = 'shift+alt+ctrl+a';
      final keybinding =
          Keybinding.parse(command).copyWith(isMetaPressed: true);
      expect(keybinding.isAltPressed, true);
      expect(keybinding.isShiftPressed, true);
      expect(keybinding.isMetaPressed, true);
      expect(keybinding.isControlPressed, true);
      expect(keybinding.keyLabel, 'a');
    });

    test('keybinding equal', () {
      const command = 'cmd+shift+alt+ctrl+a';
      expect(Keybinding.parse(command), Keybinding.parse(command));
    });

    test('keybinding toMap', () {
      const command = 'cmd+shift+alt+ctrl+a';
      final keybinding = Keybinding.parse(command);
      expect(keybinding, Keybinding.fromMap(keybinding.toMap()));
    });
  });

  // Physical ("bind to location") matching: a shortcut fires on the same key
  // POSITION regardless of the keyboard layout/language, in addition to the
  // logical character. See keybinding.dart / key_mapping.dart.
  group('keybinding physical (location) matching', () {
    test('matches on the logical key (Latin layout — unchanged)', () {
      final kb = Keybinding.parse('meta+alt+period');
      expect(
        kb.matchesKeyEvent(_event(
          logical: LogicalKeyboardKey.period,
          physical: PhysicalKeyboardKey.period,
        )),
        isTrue,
      );
    });

    test('matches on physical location when the logical key differs', () {
      // Simulates a non-Latin (e.g. Hebrew) layout: the physical period key
      // produces some other logical key, but the shortcut must still fire.
      final kb = Keybinding.parse('meta+alt+period');
      expect(
        kb.matchesKeyEvent(_event(
          logical: LogicalKeyboardKey.keyF, // whatever the layout produces
          physical: PhysicalKeyboardKey.period,
        )),
        isTrue,
      );
    });

    test('does not match a different key by either logical or physical', () {
      final kb = Keybinding.parse('meta+alt+period');
      expect(
        kb.matchesKeyEvent(_event(
          logical: LogicalKeyboardKey.comma,
          physical: PhysicalKeyboardKey.comma,
        )),
        isFalse,
      );
    });

    test('period and comma map to their real physical usages', () {
      expect(
        Keybinding.parse('period').physicalKeyCode,
        PhysicalKeyboardKey.period.usbHidUsage,
      );
      expect(
        Keybinding.parse('comma').physicalKeyCode,
        PhysicalKeyboardKey.comma.usbHidUsage,
      );
    });

    test('a key absent from the physical table falls back to logical only', () {
      // 'f1' is not in keyToPhysicalCodeMapping, so there is no physical match —
      // it behaves exactly as before (logical only).
      final kb = Keybinding.parse('f1');
      expect(kb.physicalKeyCode, isNull);
    });
  });
}
