import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_helper.dart';

// Regression test for the "hover icons sit too close to the block's text"
// bug: `actionTrailingBuilder`'s returned SizedBox is meant to reserve a
// real, undiminished gap between the drag/"+" icons and the block's text.
// This proves the mechanism actually produces that gap in the rendered
// tree (nothing in BlockComponentActionWrapper's Row swallows/collapses
// it) — it does not, and can't, prove any particular pixel value "looks
// right"; that's a human visual judgment made separately.
//
// _productionGapWidth mirrors the SizedBox width AppFlowy's app repo
// actually passes via actionTrailingBuilder (editor_configuration.dart,
// _customBlockOptionActions) — this is a separate Dart package, so it
// can't import that constant directly; keep this literal in sync by hand
// if that value changes again.

const _actionKey = Key('action');
const _gapKey = Key('gap');
const _childKey = Key('child');
const _productionGapWidth = 30.0;

Widget _buildWrapper({required double gapWidth, TextDirection? textDirection}) {
  return MaterialApp(
    home: Scaffold(
      body: BlockComponentActionWrapper(
        node: paragraphNode(text: 'hello'),
        textDirection: textDirection,
        actionBuilder: (context, state) => const SizedBox(
          key: _actionKey,
          width: 20,
          height: 20,
        ),
        actionTrailingBuilder: (context, state) => SizedBox(
          key: _gapKey,
          width: gapWidth,
          height: 20,
        ),
        child: const SizedBox(
          key: _childKey,
          width: 100,
          height: 20,
        ),
      ),
    ),
  );
}

void main() {
  group('BlockComponentActionWrapper — hover-icon gap', () {
    testWidgets(
        'actionTrailingBuilder width becomes a real, undiminished gap (LTR)',
        (tester) async {
      await tester.buildAndPump(
        _buildWrapper(gapWidth: _productionGapWidth),
      );

      final actionRight = tester.getTopRight(find.byKey(_actionKey)).dx;
      final gapLeft = tester.getTopLeft(find.byKey(_gapKey)).dx;
      final gapRight = tester.getTopRight(find.byKey(_gapKey)).dx;
      final childLeft = tester.getTopLeft(find.byKey(_childKey)).dx;

      expect(
        gapLeft,
        closeTo(actionRight, 0.5),
        reason: 'no extra space should sit between the icons and the gap',
      );
      expect(
        gapRight - gapLeft,
        closeTo(_productionGapWidth, 0.5),
        reason: 'the gap widget itself should render at its full width',
      );
      expect(
        childLeft,
        closeTo(gapRight, 0.5),
        reason: 'no extra space should sit between the gap and the text',
      );
    });

    testWidgets(
        'a wider actionTrailingBuilder produces a proportionally wider gap (LTR)',
        (tester) async {
      await tester.buildAndPump(_buildWrapper(gapWidth: 4));
      final narrowGap = tester.getTopRight(find.byKey(_gapKey)).dx -
          tester.getTopLeft(find.byKey(_gapKey)).dx;

      await tester.buildAndPump(_buildWrapper(gapWidth: 20));
      final wideGap = tester.getTopRight(find.byKey(_gapKey)).dx -
          tester.getTopLeft(find.byKey(_gapKey)).dx;

      expect(narrowGap, closeTo(4, 0.5));
      expect(wideGap, closeTo(20, 0.5));
      expect(wideGap > narrowGap, true);
    });

    testWidgets(
        'actionTrailingBuilder width becomes a real, undiminished gap (RTL)',
        (tester) async {
      await tester.buildAndPump(
        _buildWrapper(
          gapWidth: _productionGapWidth,
          textDirection: TextDirection.rtl,
        ),
      );

      // In RTL the row mirrors: icons on the right, text on the left, gap
      // still sitting undiminished between them.
      final actionLeft = tester.getTopLeft(find.byKey(_actionKey)).dx;
      final gapRight = tester.getTopRight(find.byKey(_gapKey)).dx;
      final gapLeft = tester.getTopLeft(find.byKey(_gapKey)).dx;
      final childRight = tester.getTopRight(find.byKey(_childKey)).dx;

      expect(
        gapRight,
        closeTo(actionLeft, 0.5),
        reason: 'no extra space should sit between the icons and the gap',
      );
      expect(
        gapRight - gapLeft,
        closeTo(_productionGapWidth, 0.5),
        reason: 'the gap widget itself should render at its full width',
      );
      expect(
        childRight,
        closeTo(gapLeft, 0.5),
        reason: 'no extra space should sit between the gap and the text',
      );
    });
  });
}
