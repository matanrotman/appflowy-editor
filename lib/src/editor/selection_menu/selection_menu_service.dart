import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

abstract class SelectionMenuService {
  Offset get offset;

  Alignment get alignment;

  SelectionMenuStyle get style;

  Future<void> show();

  void dismiss();

  (double? left, double? top, double? right, double? bottom) getPosition();
}

class SelectionMenu extends SelectionMenuService {
  SelectionMenu({
    required this.context,
    required this.editorState,
    required this.selectionMenuItems,
    this.deleteSlashByDefault = true,
    this.deleteKeywordsByDefault = false,
    this.style = SelectionMenuStyle.light,
    this.itemCountFilter = 0,
    this.singleColumn = false,
    this.menuHeight = 300,
    this.menuWidth = 300,
    this.menuDirection = TextDirection.ltr,
  });

  final BuildContext context;
  final EditorState editorState;
  final List<SelectionMenuItem> selectionMenuItems;
  final bool deleteSlashByDefault;
  final bool deleteKeywordsByDefault;
  final bool singleColumn;
  final double menuHeight;
  final double menuWidth;

  /// The reading direction of the block the menu is being opened from.
  ///
  /// Controls which side the menu opens/grows toward: [TextDirection.ltr]
  /// anchors from the selection's right edge and grows rightward (falling
  /// back to the left if there isn't room); [TextDirection.rtl] mirrors
  /// this, anchoring from the selection's left edge and growing leftward.
  /// Callers that don't pass this get the original LTR-only behavior.
  final TextDirection menuDirection;

  @override
  final SelectionMenuStyle style;

  OverlayEntry? _selectionMenuEntry;
  bool _selectionUpdateByInner = false;
  Offset _offset = Offset.zero;
  Alignment _alignment = Alignment.topLeft;
  int itemCountFilter;

  @override
  void dismiss() {
    if (_selectionMenuEntry != null) {
      editorState.service.keyboardService?.enable();
      editorState.service.scrollService?.enable();
    }

    _selectionMenuEntry?.remove();
    _selectionMenuEntry = null;

    // workaround: SelectionService has been released after hot reload.
    final isSelectionDisposed =
        editorState.service.selectionServiceKey.currentState == null;
    if (!isSelectionDisposed) {
      final selectionService = editorState.service.selectionService;
      // focus to reload the selection after the menu dismissed.
      editorState.selection = editorState.selection;
      selectionService.currentSelection.removeListener(_onSelectionChange);
    }
  }

  @override
  Future<void> show() async {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _show();
      completer.complete();
    });
    return completer.future;
  }

  void _show() {
    dismiss();

    final selectionService = editorState.service.selectionService;
    final selectionRects = selectionService.selectionRects;
    if (selectionRects.isEmpty) {
      return;
    }

    calculateSelectionMenuOffset(selectionRects.first);
    final (left, top, right, bottom) = getPosition();

    final editorHeight = editorState.renderBox!.size.height;
    final editorWidth = editorState.renderBox!.size.width;

    _selectionMenuEntry = OverlayEntry(
      builder: (context) {
        return SizedBox(
          width: editorWidth,
          height: editorHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              dismiss();
            },
            child: Stack(
              children: [
                Positioned(
                  top: top,
                  bottom: bottom,
                  left: left,
                  right: right,
                  // Give the scroll view an explicit width. Without it, a
                  // Positioned pinned only by `right` (the RTL "grow left"
                  // case) doesn't reliably size/grow leftward from that
                  // anchor — this path was rarely exercised before RTL
                  // support, since the original LTR-only logic almost
                  // always took the `left`-pinned "grow right" branch.
                  child: SizedBox(
                    width: menuWidth,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectionMenuWidget(
                        selectionMenuStyle: style,
                        singleColumn: singleColumn,
                        items: selectionMenuItems
                          ..forEach((element) {
                            element.deleteSlash = deleteSlashByDefault;
                            element.deleteKeywords = deleteKeywordsByDefault;
                            element.onSelected = () {
                              dismiss();
                            };
                          }),
                        maxItemInRow: 5,
                        editorState: editorState,
                        itemCountFilter: itemCountFilter,
                        menuService: this,
                        onExit: () {
                          dismiss();
                        },
                        onSelectionUpdate: () {
                          _selectionUpdateByInner = true;
                        },
                        deleteSlashByDefault: deleteSlashByDefault,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_selectionMenuEntry!);

    editorState.service.keyboardService?.disable(showCursor: true);
    editorState.service.scrollService?.disable();
    selectionService.currentSelection.addListener(_onSelectionChange);
  }

  @override
  Alignment get alignment {
    return _alignment;
  }

  @override
  Offset get offset {
    return _offset;
  }

  void _onSelectionChange() {
    // workaround: SelectionService has been released after hot reload.
    final isSelectionDisposed =
        editorState.service.selectionServiceKey.currentState == null;
    if (!isSelectionDisposed) {
      final selectionService = editorState.service.selectionService;
      if (selectionService.currentSelection.value == null) {
        return;
      }
    }

    if (_selectionUpdateByInner) {
      _selectionUpdateByInner = false;
      return;
    }

    dismiss();
  }

  @override
  (double? left, double? top, double? right, double? bottom) getPosition() {
    double? left, top, right, bottom;
    switch (alignment) {
      case Alignment.topLeft:
        left = offset.dx;
        top = offset.dy;
        break;
      case Alignment.bottomLeft:
        left = offset.dx;
        bottom = offset.dy;
        break;
      case Alignment.topRight:
        right = offset.dx;
        top = offset.dy;
        break;
      case Alignment.bottomRight:
        right = offset.dx;
        bottom = offset.dy;
        break;
    }

    return (left, top, right, bottom);
  }

  void calculateSelectionMenuOffset(Rect rect) {
    // Workaround: We can customize the padding through the [EditorStyle],
    // but the coordinates of overlay are not properly converted currently.
    // Just subtract the padding here as a result.
    const menuOffset = Offset(0, 10);
    final editorOffset =
        editorState.renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final editorHeight = editorState.renderBox!.size.height;
    final editorWidth = editorState.renderBox!.size.width;

    final isRTL = menuDirection == TextDirection.rtl;
    // In an RTL block the menu should open toward the reading direction
    // (left), so anchor from the selection's left edge instead of its
    // right edge. Everything below mirrors the LTR math horizontally.
    final bottomAnchor = isRTL ? rect.bottomLeft : rect.bottomRight;
    final topAnchor = isRTL ? rect.topLeft : rect.topRight;

    // show below default
    //
    // Note: for RTL we still use the Left-family alignments here (not
    // Right), even though the anchor is the selection's LEFT edge. The
    // Alignment.topRight/bottomRight ("pinned by `right`") code path
    // below turned out not to render correctly in practice (see the RTL
    // support spec's session log) — rather than depend on it, the RTL
    // branch further down computes an explicit `left` value for growing
    // leftward, reusing the same Left-pinned mechanism already proven
    // correct for every LTR block.
    _alignment = Alignment.topLeft;
    var offset = bottomAnchor + menuOffset;
    _offset = Offset(
      offset.dx,
      offset.dy,
    );

    // show above
    if (offset.dy + menuHeight >= editorOffset.dy + editorHeight) {
      offset = topAnchor - menuOffset;
      _alignment = Alignment.bottomLeft;

      _offset = Offset(
        offset.dx,
        editorHeight + editorOffset.dy - offset.dy,
      );
    }

    if (!isRTL) {
      // show on right
      if (_offset.dx + menuWidth < editorOffset.dx + editorWidth) {
        _offset = Offset(
          _offset.dx,
          _offset.dy,
        );
      } else if (offset.dx - editorOffset.dx > menuWidth) {
        // show on left
        _alignment = _alignment == Alignment.topLeft
            ? Alignment.topRight
            : Alignment.bottomRight;

        _offset = Offset(
          editorWidth - _offset.dx + editorOffset.dx,
          _offset.dy,
        );
      }
      return;
    }

    // RTL: default direction is "show on left" (grow toward the left from
    // the anchor). _offset.dx currently holds the anchor's raw global X,
    // which is where the menu's RIGHT edge should land — so growing left
    // means its LEFT edge (the value Alignment.topLeft/bottomLeft's `left`
    // expects) sits menuWidth further back.
    final rightEdgeX = _offset.dx;
    final fitsGrowingLeft = rightEdgeX - menuWidth > editorOffset.dx;
    if (fitsGrowingLeft) {
      _offset = Offset(rightEdgeX - menuWidth, _offset.dy);
    } else if ((editorOffset.dx + editorWidth) - rightEdgeX > menuWidth) {
      // not enough room to the left; flip to grow right instead, same as
      // the LTR default (anchor becomes the menu's left edge).
      _offset = Offset(rightEdgeX, _offset.dy);
    } else {
      // neither direction cleanly fits (very narrow editor) — fall back to
      // the default growing-left placement, matching the LTR branch's
      // equivalent fallback.
      _offset = Offset(rightEdgeX - menuWidth, _offset.dy);
    }
  }
}

final List<SelectionMenuItem> standardSelectionMenuItems = [
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.text,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'text',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['text'],
    handler: (editorState, _, __) {
      insertNodeAfterSelection(editorState, paragraphNode());
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading1,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h1',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 1, h1'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 1);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading2,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h2',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 2, h2'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 2);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading3,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h3',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 3, h3'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 3);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.image,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'image',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['image'],
    handler: (editorState, menuService, context) {
      final container = Overlay.of(context, rootOverlay: true);
      showImageMenu(container, editorState, menuService);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.bulletedList,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'bulleted_list',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['bulleted list', 'list', 'unordered list'],
    handler: (editorState, _, __) {
      insertBulletedListAfterSelection(editorState);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.numberedList,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'number',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['numbered list', 'list', 'ordered list'],
    handler: (editorState, _, __) {
      insertNumberedListAfterSelection(editorState);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.checkbox,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'checkbox',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['todo list', 'list', 'checkbox list'],
    handler: (editorState, _, __) {
      insertCheckboxAfterSelection(editorState);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.quote,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'quote',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['quote', 'refer'],
    handler: (editorState, _, __) {
      insertQuoteAfterSelection(editorState);
    },
  ),
  dividerMenuItem,
  tableMenuItem,
];

final List<SelectionMenuItem> singleColumnVisibleMenuItems = [
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.text,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'text',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['text'],
    handler: (editorState, _, __) {
      insertNodeAfterSelection(editorState, paragraphNode());
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading1,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h1',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 1, h1'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 1);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading2,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h2',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 2, h2'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 2);
    },
  ),
];
