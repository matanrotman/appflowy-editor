import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/delta_input_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// A pending font size at a bare caret (Ludwig's ribbon font-size control and
// its Cmd+Option+. / Cmd+Option+, shortcuts) must apply to the next typed
// character. `font_size` was missing from AppFlowyRichTextKeys.supportToggled,
// so onInsert's debug assertion threw and the keystroke was silently dropped —
// the same failure that made typing dead after Cmd+Tab in Ludwig (2026-09-26).
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test('a pending font size applies to the next inserted character', () async {
    final editorState = EditorState.blank();
    editorState.selection = Selection.collapsed(Position(path: [0]));
    editorState.updateToggledStyle(AppFlowyRichTextKeys.fontSize, 20.0);

    await onInsert(
      const TextEditingDeltaInsertion(
        textInserted: 'x',
        composing: TextRange.empty,
        oldText: '',
        selection: TextSelection.collapsed(offset: 1),
        insertionOffset: 0,
      ),
      editorState,
      const [],
    );

    final delta = editorState.document.nodeAtPath([0])!.delta!;
    expect(delta.toPlainText(), 'x');
    expect(
      (delta.first as TextInsert).attributes?[AppFlowyRichTextKeys.fontSize],
      20.0,
    );
  });
}
