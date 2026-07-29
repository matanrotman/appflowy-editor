import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

final List<CommandShortcutEvent> arrowLeftKeys = [
  moveCursorLeftCommand,
  moveCursorToBeginCommand,
  moveCursorToLeftWordCommand,
  moveCursorLeftSelectCommand,
  moveCursorBeginSelectCommand,
  moveCursorLeftWordSelectCommand,
];

/// Arrow left key events.
///
/// - support
///   - desktop
///   - web
///

// arrow left key
// move the cursor forward one character
final CommandShortcutEvent moveCursorLeftCommand = CommandShortcutEvent(
  key: 'move the cursor backward one character',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorLeft,
  command: 'arrow left',
  handler: _arrowLeftCommandHandler,
);

CommandShortcutEventHandler _arrowLeftCommandHandler = (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  if (moveCaretVisually(editorState, towardsLeft: true)) {
    return KeyEventResult.handled;
  }
  if (isRTL(editorState)) {
    editorState.moveCursorBackward(SelectionMoveRange.character);
  } else {
    editorState.moveCursorForward(SelectionMoveRange.character);
  }
  return KeyEventResult.handled;
};

/// Moves the caret one **visual** step, returning false when this block cannot
/// answer — at the edge of a line, in a block with no laid-out text, or in one
/// that does not implement visual traversal — so the caller falls back to the
/// existing offset arithmetic.
///
/// See `specs/bidi-caret-movement.md` in the Ludwig repo. In short: direction
/// was previously resolved once per BLOCK, so inside an English word embedded
/// in a Hebrew paragraph the left arrow travelled rightward. Movement now
/// follows the paragraph visually and never reverses.
bool moveCaretVisually(
  EditorState editorState, {
  required bool towardsLeft,
  bool byWord = false,
  bool toLineEdge = false,
}) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return false;
  }
  final position = selection.start;
  final node = editorState.getNodeAtPath(position.path);
  final selectable = node?.selectable;
  final next = selectable?.getNextVisualCaretPosition(
        position,
        towardsLeft: towardsLeft,
        byWord: byWord,
        toLineEdge: toLineEdge,
      ) ??
      (toLineEdge
          ? null
          : _crossBlockVisually(
              editorState,
              node,
              towardsLeft: towardsLeft,
            ));
  if (next == null) {
    return false;
  }
  editorState.updateSelectionWithReason(
    Selection.collapsed(next),
    reason: SelectionUpdateReason.uiEvent,
  );
  return true;
}

/// Continues the visual march into the neighbouring BLOCK, landing at the side
/// the caret would have kept moving from.
///
/// Returns null unless [VisualCaretTraversal.crossBlocksVisually] is on, so the
/// default path is untouched — see that flag for the open question this is
/// gated behind.
///
/// Which block is next follows the paragraph, not the key: reading an RTL
/// paragraph moves leftward, so leaving one to the left continues in the block
/// BELOW, while leaving an LTR paragraph to the left continues in the block
/// ABOVE. The landing edge is the mirror of the travel — leftward movement
/// arrives at the neighbour's rightmost stop — exactly as crossing a visual
/// line within a block already does.
Position? _crossBlockVisually(
  EditorState editorState,
  Node? node, {
  required bool towardsLeft,
}) {
  if (!VisualCaretTraversal.crossBlocksVisually || node == null) {
    return null;
  }
  final isRtl = node.selectable?.textDirection() == TextDirection.rtl;
  final forwards = towardsLeft ? isRtl : !isRtl;
  var neighbour = forwards
      ? node.next
      : node.previousNodeWhere((element) => element.selectable != null);
  while (neighbour != null && neighbour.selectable == null) {
    neighbour = forwards ? neighbour.next : neighbour.previous;
  }
  return neighbour?.selectable?.getVisualLineEdgeCaretPosition(
    rightmost: towardsLeft,
    firstLine: forwards,
  );
}

/// ⚠️ NOT WIRED — D2 was tried and REVERSED (user, 2026-07-28: "Looks odd, I
/// hate it").
///
/// The decision record in specs/bidi-caret-movement.md predicted exactly this:
/// in mixed text a visually-extended highlight arrives in pieces, because
/// visually adjacent letters are not adjacent in the underlying text. It was
/// built, seen, and rejected on sight — which is the fastest this could have
/// been settled, and why it was worth building rather than arguing about.
///
/// Selection therefore stays LOGICAL (contiguous highlight, Word's behaviour)
/// while the caret moves visually. Kept rather than deleted so re-wiring is one
/// line if the decision is ever revisited; do NOT re-wire it without asking.
bool extendSelectionVisually(
  EditorState editorState, {
  required bool towardsLeft,
  bool byWord = false,
  bool toLineEdge = false,
}) {
  final selection = editorState.selection;
  if (selection == null) {
    return false;
  }
  final extent = selection.end;
  final node = editorState.getNodeAtPath(extent.path);
  final next = node?.selectable?.getNextVisualCaretPosition(
    extent,
    towardsLeft: towardsLeft,
    byWord: byWord,
    toLineEdge: toLineEdge,
  );
  if (next == null) {
    return false;
  }
  editorState.updateSelectionWithReason(
    selection.copyWith(end: next),
    reason: SelectionUpdateReason.uiEvent,
  );
  return true;
}

// arrow left key + ctrl or command
// move the cursor to the beginning of the block
final CommandShortcutEvent moveCursorToBeginCommand = CommandShortcutEvent(
  key: 'move the cursor at the start of line',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorLineStart,
  command: 'home',
  macOSCommand: 'cmd+arrow left',
  handler: _moveCursorToBeginCommandHandler,
);

CommandShortcutEventHandler _moveCursorToBeginCommandHandler = (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  if (isRTL(editorState)) {
    editorState.moveCursorBackward(SelectionMoveRange.line);
  } else {
    editorState.moveCursorForward(SelectionMoveRange.line);
  }
  return KeyEventResult.handled;
};

// arrow left key + alt
// move the cursor to the left word
final CommandShortcutEvent moveCursorToLeftWordCommand = CommandShortcutEvent(
  key: 'move the cursor to the left word',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorWordLeft,
  command: 'ctrl+arrow left',
  macOSCommand: 'alt+arrow left',
  handler: _moveCursorToLeftWordCommandHandler,
);

CommandShortcutEventHandler _moveCursorToLeftWordCommandHandler =
    (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  // Word jumps follow the same visual march as the character arrows; see
  // moveCaretVisually. Falls through to the old logical arithmetic when this
  // block cannot answer.
  if (moveCaretVisually(editorState, towardsLeft: true, byWord: true)) {
    return KeyEventResult.handled;
  }

  final node = editorState.getNodeAtPath(selection.end.path);
  final delta = node?.delta;

  if (node == null || delta == null) {
    return KeyEventResult.ignored;
  }

  if (isRTL(editorState)) {
    final endOfWord = selection.end.moveHorizontal(
      editorState,
      forward: false,
      selectionRange: SelectionRange.word,
    );
    final selectedWord = delta.toPlainText().substring(
          selection.end.offset,
          endOfWord?.offset,
        );
    // check if the selected word is whitespace
    if (selectedWord.trim().isEmpty) {
      editorState.moveCursorBackward(SelectionMoveRange.word);
    }
    editorState.moveCursorBackward(SelectionMoveRange.word);
  } else {
    final startOfWord = selection.end.moveHorizontal(
      editorState,
      selectionRange: SelectionRange.word,
    );
    if (startOfWord == null) {
      return KeyEventResult.handled;
    }
    final selectedWord = delta.toPlainText().substring(
          startOfWord.offset,
          selection.end.offset,
        );
    // check if the selected word is whitespace
    if (selectedWord.trim().isEmpty) {
      editorState.moveCursorForward(SelectionMoveRange.word);
    }
    editorState.moveCursorForward(SelectionMoveRange.word);
  }
  return KeyEventResult.handled;
};

// arrow left key + alt + shift
final CommandShortcutEvent moveCursorLeftWordSelectCommand =
    CommandShortcutEvent(
  key: 'move the cursor to select the left word',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorWordLeftSelect,
  command: 'ctrl+shift+arrow left',
  macOSCommand: 'alt+shift+arrow left',
  handler: _moveCursorLeftWordSelectCommandHandler,
);

CommandShortcutEventHandler _moveCursorLeftWordSelectCommandHandler =
    (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  var forward = true;
  if (isRTL(editorState)) {
    forward = false;
  }
  final end = selection.end.moveHorizontal(
    editorState,
    selectionRange: SelectionRange.word,
    forward: forward,
  );
  if (end == null) {
    return KeyEventResult.ignored;
  }
  editorState.updateSelectionWithReason(
    selection.copyWith(end: end),
    reason: SelectionUpdateReason.uiEvent,
  );
  return KeyEventResult.handled;
};

// arrow left key + shift
// selects only one character
final CommandShortcutEvent moveCursorLeftSelectCommand = CommandShortcutEvent(
  key: 'move the cursor left select',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorLeftSelect,
  command: 'shift+arrow left',
  handler: _moveCursorLeftSelectCommandHandler,
);

CommandShortcutEventHandler _moveCursorLeftSelectCommandHandler =
    (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  var forward = true;
  if (isRTL(editorState)) {
    forward = false;
  }
  final end = selection.end.moveHorizontal(editorState, forward: forward);
  if (end == null) {
    return KeyEventResult.ignored;
  }
  editorState.updateSelectionWithReason(
    selection.copyWith(end: end),
    reason: SelectionUpdateReason.uiEvent,
  );
  return KeyEventResult.handled;
};

//
final CommandShortcutEvent moveCursorBeginSelectCommand = CommandShortcutEvent(
  key: 'move cursor to select till start of line',
  getDescription: () => AppFlowyEditorL10n.current.cmdMoveCursorLineStartSelect,
  command: 'shift+home',
  macOSCommand: 'cmd+shift+arrow left',
  handler: _moveCursorBeginSelectCommandHandler,
);

CommandShortcutEventHandler _moveCursorBeginSelectCommandHandler =
    (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  final nodes = editorState.getNodesInSelection(selection);
  if (nodes.isEmpty) {
    return KeyEventResult.ignored;
  }
  var end = selection.end;
  final position = isRTL(editorState)
      ? nodes.last.selectable?.end()
      : nodes.last.selectable?.start();
  if (position != null) {
    end = position;
  }
  editorState.updateSelectionWithReason(
    selection.copyWith(end: end),
    reason: SelectionUpdateReason.uiEvent,
  );
  return KeyEventResult.handled;
};

bool isRTL(EditorState editorState) {
  if (editorState.selection != null) {
    final node = editorState.getNodeAtPath(editorState.selection!.end.path);
    return node?.selectable?.textDirection() == TextDirection.rtl;
  }
  return false;
}
