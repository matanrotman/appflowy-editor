import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../infra/testable_editor.dart';

// Temporary probe: does the word-jump bug reproduce once the paragraph
// actually WRAPS across multiple visual lines (unlike the single-line
// probe that already passed)? Matan retested in the real app and reported
// #2/#3 still fail even after the fix that made the single-line probe
// pass — this checks whether the cross-line fallback path has the same
// class of bug.
void main() {
  group('probe: wrapped paragraph word jump', () {
    testWidgets('dump byWord traversal around האזרח and polites, wrapped',
        (tester) async {
      final filler = List.generate(30, (i) => 'מילים').join(' ');
      const sentence =
          "זו השאלה המכוננת של המסורת, ואריסטו מנסח אותה בספר ג' של "
          "הפוליטיקה: האם המידה הטובה של האדם הטוב (agathos aner) זהה "
          "לזו של האזרח הטוב (spoudaios polites)?";
      final text = '$filler $sentence';

      final editor = tester.editor
        ..addParagraph(
          initialText: text,
          decorator: (i, n) => n.updateAttributes(
            {blockComponentTextDirection: blockComponentTextDirectionAuto},
          ),
        );
      await editor.startTesting();
      final selectable = editor.nodeAtPath([0])!.selectable!;

      Rect rectAt(int offset) => selectable.getCursorRectInPosition(
            Position(path: [0], offset: offset),
          )!;
      final line1Top = rectAt(0).top;
      var lineCount = 1;
      var lastTop = line1Top;
      for (var offset = 0; offset <= text.length; offset += 5) {
        final top = rectAt(offset).top;
        if (top > lastTop + 1) {
          lineCount++;
          lastTop = top;
        }
      }
      debugPrint('approx visual line count: $lineCount');
      debugPrint('text length: ${text.length}');

      final endOfHaezrah = text.indexOf('האזרח') + 'האזרח'.length;
      final endOfPolites = text.indexOf('polites') + 'polites'.length;
      debugPrint('endOfHaezrah offset: $endOfHaezrah, '
          'top=${rectAt(endOfHaezrah).top}');
      debugPrint('endOfPolites offset: $endOfPolites, '
          'top=${rectAt(endOfPolites).top}');

      Position at(int offset) => Position(path: [0], offset: offset);

      final rightFromHaezrah = selectable.getNextVisualCaretPosition(
        at(endOfHaezrah),
        towardsLeft: false,
        byWord: true,
      );
      debugPrint(
        'option+right from end-of-האזרח ($endOfHaezrah) -> '
        '${rightFromHaezrah?.offset} '
        '(expect ${endOfHaezrah - 'האזרח'.length}, same word start)',
      );

      var cursor = at(endOfPolites);
      final walk = <int>[endOfPolites];
      for (var i = 0; i < 6; i++) {
        final next = selectable.getNextVisualCaretPosition(
          cursor,
          towardsLeft: true,
          byWord: true,
        );
        if (next == null) break;
        walk.add(next.offset);
        cursor = next;
      }
      debugPrint('leftward byWord walk from end-of-polites: $walk');

      // Overshoot probe: walk plain character-by-character rightward from
      // offset 0 and log every time the visual line changes, to see if the
      // landing offset at a line boundary is off by 1-2 characters.
      var charCursor = at(0);
      var lastLineTop = rectAt(0).top;
      final overshoots = <String>[];
      for (var i = 0; i < text.length; i++) {
        final next = selectable.getNextVisualCaretPosition(
          charCursor,
          towardsLeft: false,
        );
        if (next == null) break;
        final top = rectAt(next.offset).top;
        if (top > lastLineTop + 1) {
          overshoots.add(
            'line change at offset ${next.offset}: '
            'char="${text[next.offset.clamp(0, text.length - 1)]}"',
          );
          lastLineTop = top;
        }
        charCursor = next;
      }
      debugPrint('=== line boundaries walked (char-by-char) ===');
      for (final o in overshoots.take(10)) {
        debugPrint(o);
      }

      expect(true, isTrue);
    });
  });
}
