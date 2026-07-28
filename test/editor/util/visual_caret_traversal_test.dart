import 'package:appflowy_editor/src/editor/util/visual_caret_traversal.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// ⚠️ These tests run headless ON PURPOSE, and that is safe here for one
/// specific reason: they never lay text out. They feed [VisualCaretTraversal]
/// a hand-written list of boxes and assert the ALGORITHM.
///
/// The usual rule still stands — headless `flutter test` forces a fixed-width
/// fake font that collapses RTL geometry, so anything that measures real text
/// must run on the real macOS target. That part was done separately, in the
/// fork's `example/` app on macOS, and the coordinates below are the numbers it
/// actually produced for `שלום ABC עולם`:
///
///   offsets 5 and 8 BOTH resolve to x=38.97 and x=71.72
///
/// which is the collision this whole class exists to resolve. If a future
/// change makes these tests pass while the app misbehaves, re-measure on macOS
/// rather than trusting them.
void main() {
  // `שלום ABC עולם` laid out RTL. Visually left to right:
  //   עולם | space | A B C | space | שלום
  // Character indices are logical: ש=0 … ם=3, space=4, A=5, B=6, C=7,
  // space=8, ע=9 … ם=12.
  const rtl = TextDirection.rtl;
  const ltr = TextDirection.ltr;

  TextBox box(double left, double right, TextDirection d) =>
      TextBox.fromLTRBD(left, 0, right, 20, d);

  final line = <TextBox>[
    box(119, 130, rtl), // 0  ש
    box(108, 119, rtl), // 1  ל
    box(97, 108, rtl), // 2  ו
    box(85, 97, rtl), // 3  ם
    box(71.72, 85, rtl), // 4  space
    box(38.97, 49.9, ltr), // 5  A
    box(49.9, 60.8, ltr), // 6  B
    box(60.8, 71.72, ltr), // 7  C
    box(28, 38.97, rtl), // 8  space
    box(21, 28, rtl), // 9  ע
    box(14, 21, rtl), // 10 ו
    box(7, 14, rtl), // 11 ל
    box(0, 7, rtl), // 12 ם
  ];

  group('stopsFor', () {
    test('collapses shared edges into one stop per visual position', () {
      final stops = VisualCaretTraversal.stopsFor(line);
      // 13 glyphs sharing edges leave 14 distinct caret positions.
      expect(stops.length, 14);
      expect(stops.first, 0);
      expect(stops.last, 130);
      // Strictly increasing.
      for (var i = 1; i < stops.length; i++) {
        expect(stops[i], greaterThan(stops[i - 1]));
      }
    });

    test('the measured boundary positions are present exactly once', () {
      final stops = VisualCaretTraversal.stopsFor(line);
      expect(stops.where((s) => (s - 38.97).abs() < 0.01).length, 1);
      expect(stops.where((s) => (s - 71.72).abs() < 0.01).length, 1);
    });
  });

  group('step — the reported bug', () {
    test('marching left never reverses, and walks the English word C, B, A',
        () {
      final stops = VisualCaretTraversal.stopsFor(line);

      // Start at the end of שלום: offset 4 is the RIGHT edge of the space.
      var x = 85.0;
      final visited = <double>[];
      while (true) {
        final next = VisualCaretTraversal.step(stops, x, towardsLeft: true);
        if (next == null) break;
        visited.add(next);
        x = next;
      }

      // Every step goes strictly left. This is the whole point: today's code
      // reverses here.
      for (var i = 1; i < visited.length; i++) {
        expect(
          visited[i],
          lessThan(visited[i - 1]),
          reason: 'caret reversed at step $i of $visited',
        );
      }

      // The first four steps are the ones rendered for the user: into the
      // right edge of ABC, then B|C, then A|B, then the left edge of ABC.
      expect(visited.take(4).toList(), [71.72, 60.8, 49.9, 38.97]);
    });

    test('marching right is the mirror image', () {
      final stops = VisualCaretTraversal.stopsFor(line);
      var x = 38.97;
      final visited = <double>[];
      for (var i = 0; i < 4; i++) {
        final next = VisualCaretTraversal.step(stops, x, towardsLeft: false);
        if (next == null) break;
        visited.add(next);
        x = next;
      }
      expect(visited, [49.9, 60.8, 71.72, 85.0]);
    });

    test('returns null at each visual edge of the line', () {
      final stops = VisualCaretTraversal.stopsFor(line);
      expect(VisualCaretTraversal.step(stops, 0, towardsLeft: true), isNull);
      expect(VisualCaretTraversal.step(stops, 130, towardsLeft: false), isNull);
    });
  });

  group('sidesAt — the measured collision', () {
    test('x=71.72 is shared by offset 5 (RTL side) and 8 (LTR side)', () {
      final sides = VisualCaretTraversal.sidesAt(line, 71.72);
      expect(sides.rtl, 5, reason: 'left edge of the RTL space at index 4');
      expect(sides.ltr, 8, reason: 'right edge of C');
    });

    test('x=38.97 is shared the other way round', () {
      final sides = VisualCaretTraversal.sidesAt(line, 38.97);
      expect(sides.rtl, 8, reason: 'right edge of the RTL space at index 8');
      expect(sides.ltr, 5, reason: 'left edge of A');
    });

    test('inside a run both sides agree', () {
      final sides = VisualCaretTraversal.sidesAt(line, 49.9);
      expect(sides.ltr, 6);
      expect(sides.rtl, 6);
    });
  });

  group('insertionOffset — typing follows the character', () {
    test('a Hebrew letter at the shared stop inserts on the RTL side', () {
      final offset = VisualCaretTraversal.insertionOffset(
        line,
        71.72,
        'ח',
        paragraphDirection: rtl,
      );
      // Verified by rendering: inserting at 5 puts ח exactly at the caret.
      expect(offset, 5);
    });

    test('a Latin letter at the same stop inserts on the LTR side', () {
      final offset = VisualCaretTraversal.insertionOffset(
        line,
        71.72,
        'x',
        paragraphDirection: rtl,
      );
      // Verified by rendering: inserting at 8 puts x exactly at the caret.
      expect(offset, 8);
    });

    test('a neutral character follows the paragraph', () {
      expect(
        VisualCaretTraversal.insertionOffset(
          line,
          71.72,
          '5',
          paragraphDirection: rtl,
        ),
        5,
      );
      expect(
        VisualCaretTraversal.insertionOffset(
          line,
          71.72,
          '5',
          paragraphDirection: ltr,
        ),
        8,
      );
    });
  });

  group('restingOffset', () {
    test('defaults to the paragraph side, matching neutral insertion', () {
      expect(
        VisualCaretTraversal.restingOffset(
          line,
          71.72,
          paragraphDirection: rtl,
        ),
        5,
      );
      expect(
        VisualCaretTraversal.restingOffset(
          line,
          38.97,
          paragraphDirection: rtl,
        ),
        8,
      );
    });
  });

  group('directionOf', () {
    test('classifies the characters this rule depends on', () {
      expect(VisualCaretTraversal.directionOf('ח'), rtl);
      expect(VisualCaretTraversal.directionOf('ا'), rtl);
      expect(VisualCaretTraversal.directionOf('x'), ltr);
      expect(VisualCaretTraversal.directionOf('Q'), ltr);
      expect(VisualCaretTraversal.directionOf('é'), ltr);
      // Neutral: these must defer to the paragraph, not guess.
      expect(VisualCaretTraversal.directionOf('5'), isNull);
      expect(VisualCaretTraversal.directionOf(' '), isNull);
      expect(VisualCaretTraversal.directionOf(','), isNull);
      expect(VisualCaretTraversal.directionOf('.'), isNull);
      expect(VisualCaretTraversal.directionOf(''), isNull);
    });
  });

  group('controls — pure text is untouched', () {
    test('a pure LTR line walks right to left in plain reverse order', () {
      final ltrLine = <TextBox>[
        box(0, 10, ltr),
        box(10, 20, ltr),
        box(20, 30, ltr),
      ];
      final stops = VisualCaretTraversal.stopsFor(ltrLine);
      expect(stops, [0, 10, 20, 30]);
      expect(VisualCaretTraversal.sidesAt(ltrLine, 10).ltr, 1);
      expect(VisualCaretTraversal.sidesAt(ltrLine, 20).ltr, 2);
    });

    test('a pure RTL line maps edges the other way', () {
      final rtlLine = <TextBox>[
        box(20, 30, rtl),
        box(10, 20, rtl),
        box(0, 10, rtl),
      ];
      final stops = VisualCaretTraversal.stopsFor(rtlLine);
      expect(stops, [0, 10, 20, 30]);
      // Offset 0 sits at the RIGHT edge in RTL.
      expect(VisualCaretTraversal.sidesAt(rtlLine, 30).rtl, 0);
      expect(VisualCaretTraversal.sidesAt(rtlLine, 0).rtl, 3);
    });
  });
}
