import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

mixin BlockComponentTextDirectionMixin {
  EditorState get editorState;
  Node get node;

  TextDirection? lastDirection;

  /// Calculate the text direction of a block component.
  // defaultTextDirection will be ltr if caller hasn't passed any value.
  TextDirection calculateTextDirection({TextDirection? layoutDirection}) {
    layoutDirection ??= TextDirection.ltr;
    final defaultTextDirection = editorState.editorStyle.defaultTextDirection;

    final direction = calculateNodeDirection(
      node: node,
      layoutDirection: layoutDirection,
      defaultTextDirection: defaultTextDirection,
      lastDirection: lastDirection,
    );

    // node indent padding is added by parent node and the padding direction
    // is equal to the node text direction. when the node direction is auto
    // there is a special case which on typing text, the node direction could
    // change without any change to parent node, because no attribute of the
    // node changes as the direction attribute is auto but the calculated can
    // change to rtl or ltr. in this cases we should notify parent node to
    // recalculate the indent padding.
    if (node.level > 1 &&
        direction != lastDirection &&
        node.direction(defaultTextDirection) ==
            blockComponentTextDirectionAuto) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => node.parent?.notify());
    }
    lastDirection = direction;

    return direction;
  }
}

/// Calculate the text direction of a node.
// If the textDirection attribute is not set, we will use defaultTextDirection if
// it has a value (defaultTextDirection != null). If not will use layoutDirection.
// If the textDirection is ltr or rtl we will apply that.
// If the textDirection is auto we go by these priorities:
// 1. Determine the direction by first character with strong directionality
// 2. lastDirection which is the node last determined direction
// 3. previous line direction
// 4. defaultTextDirection
// 5. layoutDirection
// We will move from first priority when for example the node text is empty or
// it only has characters without strong directionality e.g. '@'.
TextDirection calculateNodeDirection({
  required Node node,
  required TextDirection layoutDirection,
  String? defaultTextDirection,
  TextDirection? lastDirection,
}) {
  // [fork:rtl] A PARAGRAPH's own direction wins; otherwise its FIRST STRONG
  // LETTER decides. (User rule, 2026-07-28: "Paragraph direction overrides page
  // direction and first strong letter (even pasted) dictates paragraph
  // direction.")
  //
  // Read the node's OWN attribute here rather than `node.direction(default)`,
  // which falls back to `defaultTextDirection` — the page/app default — and so
  // handed a page-level RTL setting back as though the paragraph had asked for
  // it. That short-circuited below and the text was never consulted, which is
  // why an English paragraph on an RTL page rendered RTL and its arrow keys
  // behaved as RTL. A page default is a fallback, not a per-paragraph choice.
  final ownDirection = node.attributes[blockComponentTextDirection] as String?;
  if (ownDirection != null && ownDirection != blockComponentTextDirectionAuto) {
    final direction = ownDirection.toTextDirection();
    if (direction != null) {
      return direction;
    }
  }

  // No explicit paragraph direction: the paragraph decides for itself. These
  // only refine the FALLBACK — the text still wins below when it has a strong
  // character, which is what makes pasted text take effect with no extra work
  // (a paste changes the delta, and this recomputes on the next build).
  if (lastDirection != null) {
    defaultTextDirection = lastDirection.name;
  } else {
    defaultTextDirection =
        _getDirectionFromPreviousOrParentNode(node, defaultTextDirection)
                ?.name ??
            defaultTextDirection;
  }

  final text = node.delta?.toPlainText();
  if (text != null && text.isNotEmpty) {
    final detected = determineTextDirection(text);
    if (detected != null) {
      return detected;
    }
  }

  // Empty, or nothing with strong directionality (e.g. only '@' or digits):
  // fall back to the neighbours, then the page/app default, then the layout.
  return defaultTextDirection?.toTextDirection() ?? layoutDirection;
}

TextDirection? _getDirectionFromPreviousOrParentNode(
  Node node,
  String? defaultTextDirection,
) {
  TextDirection? prevOrParentNodeDirection;
  if (node.previous != null) {
    prevOrParentNodeDirection = _getDirectionFromNode(
      node.previous!,
      defaultTextDirection,
    );
  }
  if (node.parent != null && prevOrParentNodeDirection == null) {
    prevOrParentNodeDirection = _getDirectionFromNode(
      node.parent!,
      defaultTextDirection,
    );
  }

  return prevOrParentNodeDirection;
}

TextDirection? _getDirectionFromNode(Node node, String? defaultTextDirection) {
  final nodeDirection = node.direction(
    defaultTextDirection == blockComponentTextDirectionAuto
        ? blockComponentTextDirectionAuto
        : null,
  );
  if (nodeDirection == blockComponentTextDirectionAuto) {
    // Determine straight from this node's own text rather than
    // `node.selectable?.textDirection()` — that getter (via
    // DefaultSelectableMixin) silently falls back to LTR whenever this
    // node's rich-text widget hasn't resolved a mounted state yet, which
    // happens transiently and often: right after this same node is
    // inserted/split, or while a sibling node's widget is being
    // rebuilt/recycled. Computing directly from the text has no such
    // dependency on live widget state.
    final text = node.delta?.toPlainText();
    if (text != null && text.isNotEmpty) {
      final determined = determineTextDirection(text);
      if (determined != null) {
        return determined;
      }
    }
    // No strongly-directional text of its own (empty or neutral-only) —
    // keep walking backwards through this node's own previous/parent
    // chain instead of stopping here.
    return _getDirectionFromPreviousOrParentNode(node, defaultTextDirection);
  } else {
    return nodeDirection?.toTextDirection();
  }
}

extension on Node {
  String? direction(String? defaultDirection) =>
      attributes[blockComponentTextDirection] as String? ?? defaultDirection;
}

extension on String {
  TextDirection? toTextDirection() {
    if (this == blockComponentTextDirectionLTR) {
      return TextDirection.ltr;
    } else if (this == blockComponentTextDirectionRTL) {
      return TextDirection.rtl;
    }

    return null;
  }
}
