import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../new/infra/testable_editor.dart';

// Regression test for the block-insert ("+"/slash) menu direction fix:
// SelectionMenu.calculateSelectionMenuOffset() used to always anchor from
// the selection's right edge and grow rightward, regardless of the block's
// own text direction -- opening the menu on the visually wrong side for
// RTL blocks. The fix added an optional `menuDirection` that, for RTL,
// anchors from the left edge and grows leftward (falling back to growing
// right only if there isn't room), reusing the same left-pinned
// (Alignment.topLeft/bottomLeft) positioning path already used by every
// LTR block, since the right-pinned path turned out not to render
// correctly in practice. This had no test coverage before now.

void main() {
  group('SelectionMenu.calculateSelectionMenuOffset — direction', () {
    testWidgets('LTR: anchors from the left, grows right', (tester) async {
      final editor = tester.editor..addParagraph(initialText: 'hello');
      await editor.startTesting();
      final context = tester.element(find.byType(AppFlowyEditor));

      final menu = SelectionMenu(
        context: context,
        editorState: editor.editorState,
        selectionMenuItems: const [],
        menuWidth: 100,
        menuHeight: 100,
      );

      // A narrow rect roughly in the middle of the editor, with plenty of
      // room to the right — the default/common case.
      final editorSize = editor.editorState.renderBox!.size;
      final rect = Rect.fromLTWH(editorSize.width / 2, 20, 2, 20);

      menu.calculateSelectionMenuOffset(rect);
      final (left, top, right, bottom) = menu.getPosition();

      expect(left, isNotNull, reason: 'LTR should be left-pinned by default');
      expect(right, isNull);
      expect(left, closeTo(rect.right, 0.5));

      await editor.dispose();
    });

    testWidgets(
        'RTL: anchors from the left edge of the selection, growing left',
        (tester) async {
      final editor = tester.editor..addParagraph(initialText: 'שלום');
      await editor.startTesting();
      final context = tester.element(find.byType(AppFlowyEditor));

      final menu = SelectionMenu(
        context: context,
        editorState: editor.editorState,
        selectionMenuItems: const [],
        menuWidth: 100,
        menuHeight: 100,
        menuDirection: TextDirection.rtl,
      );

      // Anchor with plenty of room on both sides, so the "fits growing
      // left" default path is exercised (not the narrow-editor fallback).
      final editorSize = editor.editorState.renderBox!.size;
      final rect = Rect.fromLTWH(editorSize.width / 2, 20, 2, 20);

      menu.calculateSelectionMenuOffset(rect);
      final (left, top, right, bottom) = menu.getPosition();

      // RTL still resolves to a `left` value (the fix deliberately stays on
      // the left-pinned Alignment path even for RTL, see file doc comment
      // above) but anchored further left than the rect itself, i.e. the
      // menu's left edge sits to the left of the selection, growing away
      // from it toward the reading direction -- the opposite of the LTR
      // case, where `left` sits at/after the rect.
      expect(left, isNotNull);
      expect(right, isNull);
      expect(
        left! < rect.left,
        true,
        reason: 'RTL menu should be anchored to the left of the selection '
            '(left=$left, rect.left=${rect.left}), growing further left, '
            'not pinned at/after the selection like the LTR case',
      );

      await editor.dispose();
    });

    testWidgets(
        'RTL vs LTR from the same rect resolve to different horizontal placement',
        (tester) async {
      final editor = tester.editor..addParagraph(initialText: 'hello שלום');
      await editor.startTesting();
      final context = tester.element(find.byType(AppFlowyEditor));
      final editorSize = editor.editorState.renderBox!.size;
      final rect = Rect.fromLTWH(editorSize.width / 2, 20, 2, 20);

      final ltrMenu = SelectionMenu(
        context: context,
        editorState: editor.editorState,
        selectionMenuItems: const [],
        menuWidth: 100,
        menuHeight: 100,
      )..calculateSelectionMenuOffset(rect);

      final rtlMenu = SelectionMenu(
        context: context,
        editorState: editor.editorState,
        selectionMenuItems: const [],
        menuWidth: 100,
        menuHeight: 100,
        menuDirection: TextDirection.rtl,
      )..calculateSelectionMenuOffset(rect);

      expect(
        ltrMenu.getPosition().$1 != rtlMenu.getPosition().$1,
        true,
        reason: 'the two directions must not resolve to the same left value '
            'from the same anchor rect',
      );

      await editor.dispose();
    });
  });
}
