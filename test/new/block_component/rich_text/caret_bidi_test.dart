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

    testWidgets(
        'caret does not split inside a date token embedded in a longer '
        'Hebrew sentence (repro from appflowy_rich_text.dart\'s comment)',
        (tester) async {
      // The original repro report was "the caret renders mid-token inside
      // a date like 20.4.26, partway through a longer Hebrew sentence."
      // This confirms that specific claim directly: within "20.4.26"
      // itself (all digits and periods, one contiguous LTR run, no bidi
      // boundary inside it), the caret must move strictly left-to-right as
      // the logical offset advances — it must not double back into the
      // token it's supposedly past.
      const text =
          'שוחחנו על זה - talking about - 20.4.26, למשל - וזה עבד מצוין';
      const token = '20.4.26';
      final start = text.indexOf(token);

      final editor = tester.editor
        ..addParagraph(
          initialText: text,
          decorator: (i, n) => n.updateAttributes(
            {blockComponentTextDirection: blockComponentTextDirectionAuto},
          ),
        );
      await editor.startTesting();

      final rects = <Rect>[
        for (var offset = start; offset <= start + token.length; offset++)
          await _caretRectAt(editor, offset),
      ];
      for (var i = 1; i < rects.length; i++) {
        expect(
          rects[i].left >= rects[i - 1].left - 0.5,
          true,
          reason: 'caret inside "$token" split mid-token: offset '
              '${start + i} (${rects[i]}) should be at/after offset '
              '${start + i - 1} (${rects[i - 1]})',
        );
      }

      await editor.dispose();
    });

    testWidgets(
        'caret leaving an embedded LTR run stays consistent with the '
        'run-entry rule above, at the exit boundary too',
        (tester) async {
      // Investigated 2026-07-14, headlessly: the boundary *entering* an
      // embedded LTR run (tested above, "sits next to the seam") behaves
      // consistently — the caret stays adjacent to the preceding run, per
      // TextAffinity.upstream. This checks the same rule holds at the
      // *exit* boundary of a run ending in trailing punctuation (the comma
      // right after "20.4.26," in the repro sentence, moving into the next
      // Hebrew word) — and it currently does not: the caret there jumps to
      // sit next to the *following* Hebrew run instead of staying adjacent
      // to the LTR run it just left, unlike every other boundary in the
      // same sentence. Tried fixing this via a per-character
      // getBoxesForSelection lookup instead of the global TextAffinity
      // flag; it produced byte-identical results, so the inconsistency
      // sits inside Flutter's own bidi run classification of the comma
      // (a weak/neutral character), not in anything this wrapper controls
      // directly. Left skipped rather than asserted-and-forced-green:
      // confirming what "correct" should look like here needs either a
      // reference implementation to compare against or a live look, not
      // another guess.
      const text =
          'שוחחנו על זה - talking about - 20.4.26, למשל - וזה עבד מצוין';
      const beforeToken = '20.4.26,';
      final exitOffset = text.indexOf(beforeToken) + beforeToken.length;

      final editor = tester.editor
        ..addParagraph(
          initialText: text,
          decorator: (i, n) => n.updateAttributes(
            {blockComponentTextDirection: blockComponentTextDirectionAuto},
          ),
        );
      await editor.startTesting();

      final atCommaEnd = await _caretRectAt(editor, exitOffset - 1);
      final afterComma = await _caretRectAt(editor, exitOffset);

      expect(
        (afterComma.left - atCommaEnd.left).abs() < 40,
        true,
        reason: 'caret just after the trailing comma in "20.4.26," '
            '($afterComma) should stay close to the comma itself '
            '($atCommaEnd), matching how every other boundary in this '
            'sentence keeps the caret adjacent to the run it just left',
      );

      await editor.dispose();
      // Skipped: confirmed real inconsistency (see comment above) but the
      // correct fix needs a live look or a reference to compare against,
      // not another blind guess — see appflowy_rich_text.dart.
    }, skip: true);
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
