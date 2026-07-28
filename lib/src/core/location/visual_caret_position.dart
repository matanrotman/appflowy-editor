import 'dart:ui' show Offset;

import 'package:appflowy_editor/src/core/location/position.dart';

/// A [Position] that also remembers **where on the line the caret actually is**.
///
/// Produced by visual caret movement (see `VisualCaretTraversal` and
/// `specs/bidi-caret-movement.md` in the Ludwig repo). It exists because a bare
/// character offset cannot locate the caret in bidirectional text: at a
/// directional boundary one offset has two homes on the line — measured, in
/// `שלום ABC עולם` offsets 5 and 8 each resolve to both x=38.97 and x=71.72 —
/// so without the x, the next arrow press recomputes from the wrong place and
/// the caret stutters or loops.
///
/// **This is a transient display hint, exactly like the pointer hint used for
/// soft-wrap disambiguation.** Deliberately:
///
///  * it does **not** participate in `==`, `hashCode` or `toJson`, all of which
///    it inherits from [Position] and which use only path + offset. Two carets
///    with the same offset stay equal, so nothing downstream changes meaning;
///  * any `copyWith` silently degrades it back to a plain [Position], which is
///    correct — a derived position has not measured anything and should fall
///    back to offset-only behaviour rather than carry a stale x.
///
/// Nothing is persisted: this never reaches the document model.
class VisualCaretPosition extends Position {
  VisualCaretPosition({
    required super.path,
    required super.offset,
    required this.visualLocalOffset,
  });

  /// Where the caret sits, in the render paragraph's local coordinates.
  ///
  /// Only `dx` is authoritative. The vertical geometry is re-derived from the
  /// offset by the renderer, which already handles line height and the
  /// empty-line placeholder correctly.
  final Offset visualLocalOffset;
}
