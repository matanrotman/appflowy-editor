import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

final List<CommandShortcutEvent> toggleMarkdownCommands = [
  toggleBoldCommand,
  toggleItalicCommand,
  toggleUnderlineCommand,
  toggleStrikethroughCommand,
  toggleCodeCommand,
];

/// Markdown key event.
///
/// Cmd / Ctrl + B: toggle bold
/// Cmd / Ctrl + I: toggle italic
/// Cmd / Ctrl + U: toggle underline
/// Cmd / Ctrl + Shift + S: toggle strikethrough
/// Cmd / Ctrl + E: code
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent toggleBoldCommand = CommandShortcutEvent(
  key: 'toggle bold',
  getDescription: () => AppFlowyEditorL10n.current.cmdToggleBold,
  command: 'ctrl+b',
  macOSCommand: 'cmd+b',
  handler: (editorState) => _toggleAttribute(
    editorState,
    AppFlowyRichTextKeys.bold,
  ),
);

final CommandShortcutEvent toggleItalicCommand = CommandShortcutEvent(
  key: 'toggle italic',
  getDescription: () => AppFlowyEditorL10n.current.cmdToggleItalic,
  command: 'ctrl+i',
  macOSCommand: 'cmd+i',
  handler: (editorState) => _toggleAttribute(
    editorState,
    AppFlowyRichTextKeys.italic,
  ),
);

final CommandShortcutEvent toggleUnderlineCommand = CommandShortcutEvent(
  key: 'toggle underline',
  getDescription: () => AppFlowyEditorL10n.current.cmdToggleUnderline,
  command: 'ctrl+u',
  macOSCommand: 'cmd+u',
  handler: (editorState) => _toggleAttribute(
    editorState,
    AppFlowyRichTextKeys.underline,
  ),
);

final CommandShortcutEvent toggleStrikethroughCommand = CommandShortcutEvent(
  key: 'toggle strikethrough',
  getDescription: () => AppFlowyEditorL10n.current.cmdToggleStrikethrough,
  command: 'ctrl+shift+s',
  macOSCommand: 'cmd+shift+s',
  handler: (editorState) => _toggleAttribute(
    editorState,
    AppFlowyRichTextKeys.strikethrough,
  ),
);

/// Briefly moved to ⌘⇧C on 2026-07-25 to free ⌘E for centre-align, then
/// reverted the same day: the user did not approve the alignment remap. Kept
/// as a note because the move also could not have worked — the app's saved
/// `shortcuts.json` pins 'toggle code' to cmd+e and overrides this default at
/// startup (see the app's `custom_text_align_command.dart`).
final CommandShortcutEvent toggleCodeCommand = CommandShortcutEvent(
  key: 'toggle code',
  getDescription: () => AppFlowyEditorL10n.current.cmdToggleCode,
  command: 'ctrl+e',
  macOSCommand: 'cmd+e',
  handler: (editorState) => _toggleAttribute(
    editorState,
    AppFlowyRichTextKeys.code,
  ),
);

KeyEventResult _toggleAttribute(
  EditorState editorState,
  String key,
) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }

  editorState.toggleAttribute(key);

  return KeyEventResult.handled;
}
