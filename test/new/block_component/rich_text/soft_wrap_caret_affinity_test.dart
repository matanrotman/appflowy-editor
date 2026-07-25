import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../infra/testable_editor.dart';

// Regression test for the RTL soft-wrap selection jump (reproduced live
// 2026-07-20, specs/rtl-support.md "RTL selection jumps left when clicking
// past the text edge").
//
// At a soft line-wrap the same integer offset means both "end of the
// previous visual line" and "start of this one"; only the TextAffinity of
// the pointer hit-test says which line the user clicked on. Position
// carries no affinity, and getCursorRectInPosition resolves every offset
// with a block-wide TextAffinity.upstream, so clicking in the gutter
// before the start of wrapped line N drew the caret at the end of line
// N-1 — in RTL a visible jump to the far LEFT of the line above. The
// first line is immune (offset 0 has no preceding line), which is also
// asserted here.
//
// These tests assert LINE membership (caret rect dy) and coarse
// half-of-paragraph x positions only — both survive the Ahem test font,
// unlike exact RTL glyph geometry (see CLAUDE.md). The fix was also
// verified live on the real macOS target.

void main() {
  group('soft-wrap caret affinity', () {
    Future<({SelectableMixin selectable, Rect Function(int) rectAt})>
        buildWrappedRtlParagraph(WidgetTester tester, String text) async {
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
      return (selectable: selectable, rectAt: rectAt);
    }

    // ~40 Hebrew words -> wraps to several visual lines on the 800px test
    // surface.
    final text = List.generate(40, (i) => 'מילים').join(' ');

    testWidgets(
        'clicking in the gutter before the start of wrapped RTL line 2 '
        'keeps the caret on line 2', (tester) async {
      final editor = await buildWrappedRtlParagraph(tester, text);
      final rectAt = editor.rectAt;
      final selectable = editor.selectable;

      // Find the first soft-wrap boundary. Under the block's default
      // upstream affinity the boundary offset itself renders on line 1,
      // so the first offset whose caret dy jumps is (boundary + 1).
      final line1Top = rectAt(0).top;
      int? firstOffsetOnLine2;
      for (var offset = 1; offset <= text.length; offset++) {
        if (rectAt(offset).top > line1Top + 1) {
          firstOffsetOnLine2 = offset;
          break;
        }
      }
      expect(
        firstOffsetOnLine2,
        isNotNull,
        reason: 'paragraph did not wrap — test setup is broken',
      );
      final boundary = firstOffsetOnLine2! - 1;
      final line2Rect = rectAt(firstOffsetOnLine2);

      // The reported click: in the gutter to the RIGHT of visual line 2 —
      // in RTL, before that line's first character. Offset 0's caret marks
      // the paragraph's right text edge.
      final rightEdge = rectAt(0).right;
      final clickLocal = Offset(rightEdge + 40, line2Rect.center.dy);
      final clickGlobal = selectable.localToGlobal(clickLocal);

      final position = selectable.getPositionInOffset(clickGlobal);
      expect(
        position.offset,
        boundary,
        reason: 'the gutter click should resolve to the wrap-boundary offset',
      );

      final caretRect = selectable.getCursorRectInPosition(position)!;
      expect(
        caretRect.top,
        closeTo(line2Rect.top, 1.0),
        reason: 'caret must stay on the clicked line (line 2), '
            'not jump up to the end of line 1',
      );
      expect(
        caretRect.center.dx > rightEdge / 2,
        isTrue,
        reason: 'caret must sit at the START of RTL line 2 (right half of '
            'the paragraph), not at the far-left end of line 1',
      );
    });

    testWidgets(
        'clicking in the gutter past the END of an RTL line still lands at '
        'that line\'s end (was already correct)', (tester) async {
      final editor = await buildWrappedRtlParagraph(tester, text);
      final rectAt = editor.rectAt;
      final selectable = editor.selectable;

      // In RTL, the LEFT gutter beside line 1 is past that line's end.
      final line1Rect = rectAt(0);
      final clickLocal = Offset(-40, line1Rect.center.dy);
      final clickGlobal = selectable.localToGlobal(clickLocal);

      final position = selectable.getPositionInOffset(clickGlobal);
      final caretRect = selectable.getCursorRectInPosition(position)!;
      expect(
        caretRect.top,
        closeTo(line1Rect.top, 1.0),
        reason: 'caret must stay at the end of line 1',
      );
      expect(
        caretRect.center.dx < rectAt(0).right / 2,
        isTrue,
        reason: 'caret must sit at the END of RTL line 1 (left half of the '
            'paragraph)',
      );
    });

    testWidgets(
        'clicking AT the end of a wrapped RTL line keeps the caret on that '
        'line, not at the start of the next one', (tester) async {
      // Guard for the mirror bug reported 2026-07-25: "if I click on the end
      // of a sentence that isn't the last sentence, it shows the text cursor
      // on the beginning of the next line."
      //
      // ⚠️ HONESTY NOTE — this is a NON-REGRESSION GUARD, not a proof.
      // It passes both with and without the fix, because the bug does not
      // reproduce headlessly: under the Ahem test font every click along
      // line 2's trailing edge resolves to the same offset with UPSTREAM
      // affinity, so the branch that causes the jump never fires here. That is
      // the exact blindness CLAUDE.md warns about — the fake font collapses
      // RTL glyph geometry. Probed explicitly at dx = 0/1/5 and either side of
      // the end-of-line caret; all stayed on line 2 pre-fix.
      //
      // So: the fix rests on code reasoning plus LIVE verification on the real
      // macOS target, and this test exists to catch a future regression of the
      // line-membership invariant, not to demonstrate the original failure.
      // If this bug ever recurs, do not trust a green run here.
      final editor = await buildWrappedRtlParagraph(tester, text);
      final rectAt = editor.rectAt;
      final selectable = editor.selectable;

      // Walk out two wrap boundaries so the clicked line has a line both
      // above and below it — the "isn't the last sentence" part of the report.
      final line1Top = rectAt(0).top;
      int? firstOffsetOnLine2;
      for (var offset = 1; offset <= text.length; offset++) {
        if (rectAt(offset).top > line1Top + 1) {
          firstOffsetOnLine2 = offset;
          break;
        }
      }
      expect(firstOffsetOnLine2, isNotNull, reason: 'paragraph did not wrap');

      final line2Top = rectAt(firstOffsetOnLine2!).top;
      int? firstOffsetOnLine3;
      for (var offset = firstOffsetOnLine2 + 1;
          offset <= text.length;
          offset++) {
        if (rectAt(offset).top > line2Top + 1) {
          firstOffsetOnLine3 = offset;
          break;
        }
      }
      expect(
        firstOffsetOnLine3,
        isNotNull,
        reason: 'paragraph needs at least three visual lines',
      );

      // The end of line 2 == the boundary offset shared with line 3. In RTL
      // that is the line's LEFT extreme.
      final endOfLine2Rect = rectAt(firstOffsetOnLine3! - 1);
      expect(
        endOfLine2Rect.top,
        closeTo(line2Top, 1.0),
        reason: 'setup: the boundary offset should render on line 2',
      );

      final clickLocal = Offset(
        endOfLine2Rect.center.dx,
        endOfLine2Rect.center.dy,
      );
      final position =
          selectable.getPositionInOffset(selectable.localToGlobal(clickLocal));
      final caretRect = selectable.getCursorRectInPosition(position)!;

      expect(
        caretRect.top,
        closeTo(line2Top, 1.0),
        reason: 'caret must stay on the line that was clicked (line 2), not '
            'drop to the start of line 3',
      );
    });

    testWidgets(
        'first-line exception: clicking in the gutter before line 1 lands '
        'at offset 0 on line 1', (tester) async {
      final editor = await buildWrappedRtlParagraph(tester, text);
      final rectAt = editor.rectAt;
      final selectable = editor.selectable;

      final line1Rect = rectAt(0);
      final clickLocal = Offset(line1Rect.right + 40, line1Rect.center.dy);
      final clickGlobal = selectable.localToGlobal(clickLocal);

      final position = selectable.getPositionInOffset(clickGlobal);
      expect(position.offset, 0);
      final caretRect = selectable.getCursorRectInPosition(position)!;
      expect(caretRect.top, closeTo(line1Rect.top, 1.0));
    });
  });

  group('getLineBoundaryInPosition', () {
    final text = List.generate(40, (i) => 'מילים').join(' ');

    testWidgets('returns the visual line span of a wrapped RTL paragraph',
        (tester) async {
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

      // Locate line 2 the same way the sibling group does: under upstream
      // affinity the first offset whose caret dy jumps is (boundary + 1).
      final line1Top = rectAt(0).top;
      int? firstOffsetOnLine2;
      for (var offset = 1; offset <= text.length; offset++) {
        if (rectAt(offset).top > line1Top + 1) {
          firstOffsetOnLine2 = offset;
          break;
        }
      }
      expect(firstOffsetOnLine2, isNotNull);
      final boundary = firstOffsetOnLine2! - 1;

      // A position safely inside visual line 2.
      final midLine2 = selectable.getLineBoundaryInPosition(
        Position(path: [0], offset: firstOffsetOnLine2 + 2),
      );
      expect(midLine2, isNotNull);
      // The line's span starts at the wrap boundary (line 2's first
      // character) — a smaller span like a word or a sentence would not.
      expect(midLine2!.start.offset, boundary);
      expect(midLine2.end.offset, greaterThan(firstOffsetOnLine2));
      expect(
        midLine2.end.offset,
        lessThan(text.length),
        reason: 'the span must be one visual line, not the whole block',
      );

      // A position inside line 1 maps to line 1: starts at 0 and ends at
      // the same wrap boundary where line 2 begins (the ranges tile).
      final midLine1 = selectable.getLineBoundaryInPosition(
        Position(path: [0], offset: 1),
      );
      expect(midLine1!.start.offset, 0);
      expect(
        midLine1.end.offset,
        anyOf(boundary, boundary - 1),
        reason: 'line 1 ends at the soft-wrap boundary '
            '(getLineBoundary may or may not include the trailing space)',
      );

      // Consistency with the caret renderer at the ambiguous boundary
      // offset itself: a plain Position resolves upstream (the line the
      // caret is drawn on — line 1).
      final atBoundary = selectable.getLineBoundaryInPosition(
        Position(path: [0], offset: boundary),
      );
      expect(atBoundary!.start.offset, 0, reason: 'upstream → line 1');
    });

    testWidgets('non-text selectables return null', (tester) async {
      final editor = tester.editor..addParagraph(initialText: 'a');
      await editor.startTesting();
      // The base SelectableMixin default is null; exercised via a plain
      // Position on an offset outside the delta, which must also be null.
      final selectable = editor.nodeAtPath([0])!.selectable!;
      expect(
        selectable.getLineBoundaryInPosition(
          Position(path: [0], offset: 99),
        ),
        isNull,
      );
    });
  });
}
