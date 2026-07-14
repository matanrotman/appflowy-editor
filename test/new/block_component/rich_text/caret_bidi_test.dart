import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../infra/testable_editor.dart';

// Regression tests for two RTL caret-rendering bugs:
// 1. The caret used to render mid-character at a bidi run boundary (e.g.
//    where Hebrew text meets an embedded English word), because
//    `getCursorRectInPosition` never set an explicit `TextAffinity`.
// 2. The caret on an empty RTL line used to render near the block's left
//    edge instead of its right edge, because the empty-line correction was
//    gated on `placeholderText.trim().isNotEmpty`, which the default
//    single-space placeholder never satisfied.
// Both were fixed by making `TextAffinity.upstream` explicit and basing the
// empty-line correction on the real content width instead of the
// placeholder text. These tests exist because, before this session, no test
// asserted anything about caret rect *position* at all.

Future<Rect> _caretRectAt(TestableEditor editor, int offset) async {
  await editor.updateSelection(
    Selection.collapsed(Position(path: [0], offset: offset)),
  );
  final rect = editor.editorState.selectionRects().firstOrNull;
  expect(rect, isNotNull, reason: 'no caret rect at offset $offset');
  return rect!;
}

void main() {
  group('caret position — bidi run boundary', () {
    testWidgets('non-regression: pure LTR line moves left-to-right',
        (tester) async {
      final editor = tester.editor
        ..addParagraph(
          initialText: 'Hello',
          decorator: (i, n) => n.updateAttributes(
            {blockComponentTextDirection: blockComponentTextDirectionAuto},
          ),
        );
      await editor.startTesting();

      final rects = <Rect>[
        for (var offset = 0; offset <= 5; offset++)
          await _caretRectAt(editor, offset),
      ];
      for (var i = 1; i < rects.length; i++) {
        expect(
          rects[i].left >= rects[i - 1].left,
          true,
          reason: 'offset $i (${rects[i]}) should be at/after '
              'offset ${i - 1} (${rects[i - 1]}) in an LTR line',
        );
      }

      await editor.dispose();
    });

    testWidgets('non-regression: pure RTL line moves right-to-left',
        (tester) async {
      final editor = tester.editor
        ..addParagraph(
          initialText: 'שלום',
          decorator: (i, n) => n.updateAttributes(
            {blockComponentTextDirection: blockComponentTextDirectionAuto},
          ),
        );
      await editor.startTesting();

      final rects = <Rect>[
        for (var offset = 0; offset <= 4; offset++)
          await _caretRectAt(editor, offset),
      ];
      for (var i = 1; i < rects.length; i++) {
        expect(
          rects[i].left <= rects[i - 1].left,
          true,
          reason: 'offset $i (${rects[i]}) should be at/before '
              'offset ${i - 1} (${rects[i - 1]}) in an RTL line',
        );
      }

      await editor.dispose();
    });

    testWidgets(
        'caret at a Hebrew/English boundary sits next to the seam, '
        'not inside the following run', (tester) async {
      const hebrew = 'שלום';
      const latin = 'Hello';
      final boundaryOffset = hebrew.length;

      final editor = tester.editor
        ..addParagraph(
          initialText: '$hebrew$latin',
          decorator: (i, n) => n.updateAttributes(
            {blockComponentTextDirection: blockComponentTextDirectionAuto},
          ),
        );
      await editor.startTesting();

      final beforeBoundary = await _caretRectAt(editor, boundaryOffset - 1);
      final atBoundary = await _caretRectAt(editor, boundaryOffset);
      final afterBoundary = await _caretRectAt(editor, boundaryOffset + 1);

      final distToHebrewSide = (atBoundary.left - beforeBoundary.left).abs();
      final distToLatinSide = (atBoundary.left - afterBoundary.left).abs();

      expect(
        distToHebrewSide < distToLatinSide,
        true,
        reason: 'boundary caret $atBoundary should sit closer to the '
            'preceding Hebrew-run caret $beforeBoundary (dist='
            '$distToHebrewSide) than to the following Latin-run caret '
            '$afterBoundary (dist=$distToLatinSide) — a caret that split '
            'mid-character would land far closer to the Latin side',
      );

      await editor.dispose();
    });
  });

  group('caret position — empty line', () {
    testWidgets(
        'empty RTL paragraph caret sits near where typing will actually land',
        (tester) async {
      final editor = tester.editor
        ..addParagraph(
          initialText: '',
          decorator: (i, n) => n.updateAttributes(
            {blockComponentTextDirection: blockComponentTextDirectionRTL},
          ),
        );
      await editor.startTesting();

      final emptyRect = await _caretRectAt(editor, 0);

      await editor.updateSelection(
        Selection.collapsed(Position(path: [0], offset: 0)),
      );
      await editor.ime.typeText('א');
      await tester.pumpAndSettle();

      final typedRect = editor.editorState.selectionRects().firstOrNull;
      expect(typedRect, isNotNull);

      expect(
        (emptyRect.left - typedRect!.left).abs() < 60,
        true,
        reason: 'empty-line caret $emptyRect should be near the caret '
            'after typing $typedRect (within ~one character), not off on '
            'the opposite side of the block',
      );

      await editor.dispose();
    });

    testWidgets(
        'empty RTL heading caret also sits near where typing will land '
        '(not just the default paragraph placeholder)', (tester) async {
      final editor = tester.editor
        ..addNode(
          headingNode(
            level: 1,
            delta: Delta(),
            textDirection: blockComponentTextDirectionRTL,
          ),
        );
      await editor.startTesting();

      final emptyRect = await _caretRectAt(editor, 0);

      await editor.updateSelection(
        Selection.collapsed(Position(path: [0], offset: 0)),
      );
      await editor.ime.typeText('א');
      await tester.pumpAndSettle();

      final typedRect = editor.editorState.selectionRects().firstOrNull;
      expect(typedRect, isNotNull);

      expect(
        (emptyRect.left - typedRect!.left).abs() < 60,
        true,
        reason: 'empty-line caret $emptyRect should be near the caret '
            'after typing $typedRect',
      );

      await editor.dispose();
    });

    testWidgets(
        'empty LTR paragraph caret sits near where typing will land '
        '(sanity baseline)', (tester) async {
      final editor = tester.editor
        ..addParagraph(
          initialText: '',
          decorator: (i, n) => n.updateAttributes(
            {blockComponentTextDirection: blockComponentTextDirectionLTR},
          ),
        );
      await editor.startTesting();

      final emptyRect = await _caretRectAt(editor, 0);

      await editor.updateSelection(
        Selection.collapsed(Position(path: [0], offset: 0)),
      );
      await editor.ime.typeText('a');
      await tester.pumpAndSettle();

      final typedRect = editor.editorState.selectionRects().firstOrNull;
      expect(typedRect, isNotNull);

      expect(
        (emptyRect.left - typedRect!.left).abs() < 60,
        true,
        reason: 'empty-line caret $emptyRect should be near the caret '
            'after typing $typedRect',
      );

      await editor.dispose();
    });
  });
}
