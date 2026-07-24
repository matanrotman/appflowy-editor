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
}
