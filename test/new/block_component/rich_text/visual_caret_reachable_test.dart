import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../infra/testable_editor.dart';

// Does visual caret movement actually REACH a real block component?
//
// This asks a structural question, not a geometric one, so it is safe under the
// Ahem test font: it only checks that `getNextVisualCaretPosition` returns
// something rather than null. Exact positions are measured on the real macOS
// target instead (see specs/bidi-caret-movement.md).
//
// It exists because the first two attempts at shipping this both failed HERE
// rather than in the algorithm: the primitive was correct and fully tested, and
// the app silently fell back to the old behaviour because the call never
// arrived. `SelectableMixin.getNextVisualCaretPosition` defaults to null and
// `DefaultSelectableMixin` forwards method by method, so any gap in that chain
// is invisible — no error, no warning, just the old behaviour.
void main() {
  group('visual caret movement is reachable from a real block component', () {
    testWidgets('a paragraph answers getNextVisualCaretPosition', (t) async {
      final editor = t.editor
        ..addParagraph(
          initialText: 'שלום ABC עולם',
          decorator: (i, n) => n.updateAttributes(
            {blockComponentTextDirection: blockComponentTextDirectionAuto},
          ),
        );
      await editor.startTesting();

      final selectable = editor.nodeAtPath([0])!.selectable!;
      final from = Position(path: [0], offset: 6);

      final left = selectable.getNextVisualCaretPosition(
        from,
        towardsLeft: true,
      );
      final right = selectable.getNextVisualCaretPosition(
        from,
        towardsLeft: false,
      );

      expect(
        left,
        isNotNull,
        reason: 'null means the block fell back to the old offset arithmetic — '
            'check that DefaultSelectableMixin forwards this method',
      );
      expect(right, isNotNull);
      expect(left, isA<VisualCaretPosition>());

      await editor.dispose();
    });

    testWidgets('a heading answers it too (it shares the same mixin chain)',
        (t) async {
      final editor = t.editor
        ..addNode(
          headingNode(level: 1, text: 'שלום ABC עולם'),
        );
      await editor.startTesting();

      final selectable = editor.nodeAtPath([0])!.selectable!;
      final next = selectable.getNextVisualCaretPosition(
        Position(path: [0], offset: 6),
        towardsLeft: true,
      );
      expect(next, isNotNull);

      await editor.dispose();
    });
  });
}
