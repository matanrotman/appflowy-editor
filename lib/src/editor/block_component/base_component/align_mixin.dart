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
}
