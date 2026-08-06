import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

mixin BlockComponentAlignMixin {
  Node get node;

  Alignment? get alignment {
    final alignString = node.attributes[blockComponentAlign] as String?;
    switch (alignString) {
      case 'center':
        return Alignment.center;

      case 'right':
        return Alignment.centerRight;

      case 'left':
        return Alignment.centerLeft;
      // 'justify' intentionally returns null here: it is a *text* instruction,
      // not a box position, so the block keeps its full width and the text
      // stretches inside it (see [blockTextAlign]).
      default:
        return null;
    }
  }

  /// [fork:ribbon] specs/ribbon-menu.md (Phase 4).
  ///
  /// The align value mapped **directly** to a [TextAlign], bypassing the
  /// [Alignment] hop that [alignment] takes for box positioning. That hop cannot
  /// represent justify (an [Alignment] is a position, not a paragraph-layout
  /// rule), which is why justify needs this parallel getter. For left/center/
  /// right it matches what `alignment?.toTextAlign` produced before, so existing
  /// behaviour is unchanged; `null` (no align set) lets callers fall back to the
  /// configured default.
  TextAlign? get blockTextAlign {
    final alignString = node.attributes[blockComponentAlign] as String?;
    switch (alignString) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      case 'left':
        return TextAlign.left;
      case 'justify':
        return TextAlign.justify;
      default:
        return null;
    }
  }

  /// [fork:ribbon] specs/ribbon-menu.md (Phase 4, gap found 2026-07-25).
  ///
  /// Whether this block is justified, and therefore whether its text child must
  /// be laid out **tight** rather than shrink-wrapped.
  ///
  /// Every component that renders a leading marker (bullet, number, checkbox,
  /// quote bar, heading toggle) puts its text in a `Flexible` inside a
  /// `Row(mainAxisSize: MainAxisSize.min)`. A loose `Flexible` lets the text
  /// size to its *intrinsic* width, so there is no slack for justify to
  /// distribute and the paragraph renders identically to a plain start-aligned
  /// one — which is exactly what "justify does nothing in a bulleted list"
  /// looked like. Paragraph blocks have no such Row, which is why they were the
  /// only ones where justify appeared to work.
  ///
  /// Callers use this to pick the flex fit. It is deliberately scoped to the
  /// justify case: every other alignment keeps the existing loose layout
  /// byte-for-byte, so this cannot regress box positioning (see [alignment]) or
  /// widen a list row that used to hug its text.
  bool get isJustified => blockTextAlign == TextAlign.justify;
}
