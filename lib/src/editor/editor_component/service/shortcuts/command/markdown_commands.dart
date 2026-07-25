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

/// [fork:ribbon] Moved off ⌘E on 2026-07-25 (user's request): the alignment
/// shortcuts adopted Word's ⌘L / ⌘E / ⌘R / ⌘J, and centre-align claimed ⌘E.
///
/// ⌘⇧E was the obvious next door but is already the app's math-equation
/// shortcut, so inline code landed on ⌘⇧C — free in both the app and this
/// package, mnemonic, and the same chord Slack uses for inline code. Inline
/// code also remains reachable from the ribbon and from markdown backticks.
final CommandShortcutEvent toggleCodeCommand = CommandShortcutEvent(
  key: 'toggle code',
  getDescription: () => AppFlowyEditorL10n.current.cmdToggleCode,
  command: 'ctrl+shift+c',
  macOSCommand: 'cmd+shift+c',
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
