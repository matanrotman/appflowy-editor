import 'package:appflowy_editor/src/service/selection/selection_gesture.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helper.dart';

void main() {
  group('SelectionGestureDetector (desktop)', () {
    testWidgets('fires triple tap for three quick taps', (tester) async {
      var tripleTaps = 0;
      await tester.buildAndPump(
        SelectionGestureDetector(
          onTripleTapDown: (_) => tripleTaps++,
          child: const SizedBox.square(dimension: 50),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.byType(SizedBox);
      await tester.tap(target, warnIfMissed: false);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(target, warnIfMissed: false);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(target, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tripleTaps, 1);
    });

    // Regression (app user report, 2026-07-23): the triple-tap window used to be
    // anchored to the FIRST tap, so a natural "double-click a word, glance, then
    // click for the paragraph" exceeded the budget and the third click was
    // treated as a fresh single tap. The window is now measured from the
    // previous tap, so a pause AFTER the double-click still completes the triple.
    testWidgets('third tap still counts after a pause following the double-tap',
        (tester) async {
      var tripleTaps = 0;
      var doubleTaps = 0;
      await tester.buildAndPump(
        SelectionGestureDetector(
          onDoubleTapDown: (_) => doubleTaps++,
          onTripleTapDown: (_) => tripleTaps++,
          child: const SizedBox.square(dimension: 50),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.byType(SizedBox);
      // A double-tap selects the word. The two taps are ~250ms apart — a real,
      // unhurried double-click, still within kDoubleTapTimeout (300ms).
      await tester.tap(target, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(target, warnIfMissed: false);
      // ...then the user pauses to look before the third click. At 350ms after
      // the double-tap this is PAST the old window (which ended 500ms after the
      // FIRST tap, i.e. ~250ms after the double-tap) but within the new window
      // measured from the double-tap. Old code: single. New code: triple.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(target, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(doubleTaps, 1);
      expect(
        tripleTaps,
        1,
        reason: 'the paused third click should complete the triple',
      );
    });

    testWidgets('a slow third tap beyond the window is not a triple',
        (tester) async {
      var tripleTaps = 0;
      await tester.buildAndPump(
        SelectionGestureDetector(
          onTripleTapDown: (_) => tripleTaps++,
          child: const SizedBox.square(dimension: 50),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.byType(SizedBox);
      await tester.tap(target, warnIfMissed: false);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(target, warnIfMissed: false);
      // Well beyond kTripleTapTimeout (500ms) after the double-tap.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(target, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tripleTaps, 0);
    });
  });
}
