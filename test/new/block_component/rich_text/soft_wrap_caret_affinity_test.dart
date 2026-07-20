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
}
