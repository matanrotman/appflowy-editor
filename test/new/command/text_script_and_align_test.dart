import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/util.dart';

/// [fork:ribbon] specs/ribbon-menu.md (Phase 4).
///
/// Covers the pure logic added for Phase 4: the mutually-exclusive
/// superscript/subscript toggle, and the align-string → TextAlign mapping that
/// lets justify survive (the [Alignment] hop cannot represent it). The *visual*
/// rendering (FontFeature super/subscript, justified stretching) is verified on
/// the real macOS target, not here.

/// Minimal host for [BlockComponentAlignMixin] so its getters can be tested
/// without pumping a whole block component.
class _AlignHost with BlockComponentAlignMixin {
  _AlignHost(this.node);

  @override
  final Node node;
}

Node _paragraph({String? align}) {
  return paragraphNode(
    text: 'The quick brown fox',
    attributes: {
      'delta': (Delta()..insert('The quick brown fox')).toJson(),
      if (align != null) blockComponentAlign: align,
    },
  );
}

bool _rangeHas(EditorState editorState, Selection selection, String key) {
  final node = editorState.getNodeAtPath(selection.start.path)!;
  return node.allSatisfyInSelection(
    selection,
    (delta) => delta
        .whereType<TextInsert>()
        .every((i) => i.attributes?[key] == true),
  );
}

bool _rangeAbsent(EditorState editorState, Selection selection, String key) {
  final node = editorState.getNodeAtPath(selection.start.path)!;
  return node.allSatisfyInSelection(
    selection,
    (delta) => delta
        .whereType<TextInsert>()
        .every((i) => i.attributes?[key] != true),
  );
}

void main() {
  group('toggleExclusiveAttribute (superscript / subscript)', () {
    const text = 'H2O';
    Selection wholeLine() => Selection.single(
          path: [0],
          startOffset: 0,
          endOffset: text.length,
        );

    test('enabling superscript sets it on the range', () async {
      final editorState = EditorState(
        document: Document.blank().addParagraph(initialText: text),
      );
      editorState.selection = wholeLine();

      await editorState.toggleExclusiveAttribute(
        AppFlowyRichTextKeys.superscript,
        AppFlowyRichTextKeys.subscript,
      );

      expect(
        _rangeHas(editorState, wholeLine(), AppFlowyRichTextKeys.superscript),
        isTrue,
      );
    });

    test('toggling superscript twice removes it', () async {
      final editorState = EditorState(
        document: Document.blank().addParagraph(initialText: text),
      );
      editorState.selection = wholeLine();

      await editorState.toggleExclusiveAttribute(
        AppFlowyRichTextKeys.superscript,
        AppFlowyRichTextKeys.subscript,
      );
      await editorState.toggleExclusiveAttribute(
        AppFlowyRichTextKeys.superscript,
        AppFlowyRichTextKeys.subscript,
      );

      expect(
        _rangeAbsent(editorState, wholeLine(), AppFlowyRichTextKeys.superscript),
        isTrue,
      );
    });

    test('enabling subscript clears an existing superscript (mutually exclusive)',
        () async {
      final editorState = EditorState(
        document: Document.blank().addParagraph(initialText: text),
      );
      editorState.selection = wholeLine();

      // Start with superscript on.
      await editorState.toggleExclusiveAttribute(
        AppFlowyRichTextKeys.superscript,
        AppFlowyRichTextKeys.subscript,
      );
      expect(
        _rangeHas(editorState, wholeLine(), AppFlowyRichTextKeys.superscript),
        isTrue,
      );

      // Now turn on subscript — superscript must be cleared.
      await editorState.toggleExclusiveAttribute(
        AppFlowyRichTextKeys.subscript,
        AppFlowyRichTextKeys.superscript,
      );

      expect(
        _rangeHas(editorState, wholeLine(), AppFlowyRichTextKeys.subscript),
        isTrue,
        reason: 'subscript should now be on',
      );
      expect(
        _rangeAbsent(editorState, wholeLine(), AppFlowyRichTextKeys.superscript),
        isTrue,
        reason: 'superscript should have been cleared',
      );
    });
  });

  group('blockTextAlign (justify survives the Alignment hop)', () {
    test('justify maps to TextAlign.justify', () {
      expect(_AlignHost(_paragraph(align: 'justify')).blockTextAlign,
          TextAlign.justify);
    });

    test('left / center / right match the pre-Phase-4 behaviour', () {
      expect(_AlignHost(_paragraph(align: 'left')).blockTextAlign,
          TextAlign.left);
      expect(_AlignHost(_paragraph(align: 'center')).blockTextAlign,
          TextAlign.center);
      expect(_AlignHost(_paragraph(align: 'right')).blockTextAlign,
          TextAlign.right);
    });

    test('no align set → null (caller falls back to its default)', () {
      expect(_AlignHost(_paragraph()).blockTextAlign, isNull);
    });

    test('justify keeps the block full-width: box alignment stays null', () {
      // A justified paragraph must not be box-shifted; only the text stretches.
      expect(_AlignHost(_paragraph(align: 'justify')).alignment, isNull);
    });
  });

  group('isJustified (tight flex fit for marker-bearing blocks)', () {
    // Regression guard for the 2026-07-25 finding: justify did nothing inside
    // bulleted/numbered/todo/quote/heading blocks, because each puts its text in
    // a loose `Flexible` inside a `Row(mainAxisSize: MainAxisSize.min)`. A loose
    // child shrink-wraps to its intrinsic width, leaving justify no slack to
    // distribute. Those components now pick `FlexFit.tight` off this getter.
    test('is true only for justify', () {
      expect(_AlignHost(_paragraph(align: 'justify')).isJustified, isTrue);
    });

    test('every other alignment stays loose, so layout is unchanged', () {
      // This is the important half: scoping the tight fit to justify alone is
      // what guarantees the fix cannot widen a list row that used to hug its
      // text, or disturb the box positioning that left/center/right rely on.
      for (final align in ['left', 'center', 'right']) {
        expect(
          _AlignHost(_paragraph(align: align)).isJustified,
          isFalse,
          reason: '$align must keep the pre-fix loose layout',
        );
      }
      expect(_AlignHost(_paragraph()).isJustified, isFalse);
    });
  });
}
