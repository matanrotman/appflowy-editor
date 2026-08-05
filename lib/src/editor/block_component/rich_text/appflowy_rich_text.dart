import 'dart:math';
import 'dart:ui';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef TextSpanDecoratorForAttribute = InlineSpan Function(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
);

typedef AppFlowyTextSpanDecorator = TextSpan Function(TextSpan textSpan);
typedef AppFlowyAutoCompleteTextProvider = String? Function(
  BuildContext context,
  Node node,
  TextSpan? textSpan,
);

typedef AppFlowyTextSpanOverlayBuilder = List<Widget> Function(
  BuildContext context,
  Node node,
  SelectableMixin delegate,
);

class AppFlowyRichText extends StatefulWidget {
  const AppFlowyRichText({
    super.key,
    this.cursorHeight,
    this.cursorWidth = 2.0,
    this.lineHeight,
    this.textSpanDecorator,
    this.placeholderText = ' ',
    this.placeholderTextSpanDecorator,
    this.textDirection = TextDirection.ltr,
    this.textSpanDecoratorForCustomAttributes,
    this.textSpanOverlayBuilder,
    this.textAlign,
    this.cursorColor = const Color.fromARGB(255, 0, 0, 0),
    this.selectionColor = const Color.fromARGB(53, 111, 201, 231),
    this.autoCompleteTextProvider,
    required this.delegate,
    required this.node,
    required this.editorState,
  });

  /// The node of the rich text.
  final Node node;

  /// The editor state.
  final EditorState editorState;

  /// The height of the cursor.
  ///
  /// If this is null, the height of the cursor will be calculated automatically.
  final double? cursorHeight;

  /// The width of the cursor.
  final double cursorWidth;

  /// The height of each line.
  final double? lineHeight;

  /// customize the text span for rich text
  final AppFlowyTextSpanDecorator? textSpanDecorator;

  /// The placeholder text when the rich text is empty.
  final String placeholderText;

  /// customize the text span for placeholder text
  final AppFlowyTextSpanDecorator? placeholderTextSpanDecorator;

  final TextAlign? textAlign;

  // get the cursor rect, selection rects or block rect from the delegate
  final SelectableMixin delegate;

  // this span will be appended to the current text span, mostly, it is used for auto complete
  final AppFlowyAutoCompleteTextProvider? autoCompleteTextProvider;

  /// customize the text span for custom attributes
  ///
  /// You can use this to customize the text span for custom attributes
  ///   or override the existing one.
  final TextSpanDecoratorForAttribute? textSpanDecoratorForCustomAttributes;

  /// customize the text span overlay builder
  ///
  /// You can use this to customize the text span overlay, for example, a hover menu in linked text.
  final AppFlowyTextSpanOverlayBuilder? textSpanOverlayBuilder;

  final TextDirection textDirection;

  final Color cursorColor;
  final Color selectionColor;

  @override
  State<AppFlowyRichText> createState() => _AppFlowyRichTextState();
}

class _AppFlowyRichTextState extends State<AppFlowyRichText>
    with SelectableMixin {
  final textKey = GlobalKey();
  final placeholderTextKey = GlobalKey();

  RenderParagraph? get _renderParagraph =>
      textKey.currentContext?.findRenderObject() as RenderParagraph?;

  RenderParagraph? get _placeholderRenderParagraph =>
      placeholderTextKey.currentContext?.findRenderObject() as RenderParagraph?;

  TextSpanDecoratorForAttribute? get textSpanDecoratorForAttribute =>
      widget.textSpanDecoratorForCustomAttributes ??
      widget.editorState.editorStyle.textSpanDecorator;

  AppFlowyAutoCompleteTextProvider? get autoCompleteTextProvider =>
      widget.autoCompleteTextProvider ??
      widget.editorState.autoCompleteTextProvider;

  bool get enableAutoComplete =>
      widget.editorState.enableAutoComplete && autoCompleteTextProvider != null;

  TextStyleConfiguration get textStyleConfiguration =>
      widget.editorState.editorStyle.textStyleConfiguration;

  AppFlowyTextSpanOverlayBuilder? get textSpanOverlayBuilder =>
      widget.textSpanOverlayBuilder ??
      widget.editorState.editorStyle.textSpanOverlayBuilder;

  @override
  void initState() {
    super.initState();
    confirmContextEnabled();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Stack(
      children: [
        _buildPlaceholderText(context),
        _buildRichText(context),
        ..._buildRichTextOverlay(context),
      ],
    );

    if (enableAutoComplete) {
      final autoCompleteText = _buildAutoCompleteRichText();
      child = Stack(
        children: [
          autoCompleteText,
          child,
        ],
      );
    }

    return BlockSelectionContainer(
      delegate: widget.delegate,
      listenable: widget.editorState.selectionNotifier,
      remoteSelection: widget.editorState.remoteSelections,
      node: widget.node,
      cursorColor: widget.cursorColor,
      selectionColor: widget.selectionColor,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: child,
      ),
    );
  }

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(
        path: widget.node.path,
        offset: widget.node.delta?.toPlainText().length ?? 0,
      );

  @override
  Rect getBlockRect({
    bool shiftWithBaseOffset = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    if (kDebugMode && _renderParagraph?.debugNeedsLayout == true) {
      return null;
    }

    final delta = widget.node.delta;
    if (position.offset < 0 ||
        (delta != null && position.offset > delta.length)) {
      return null;
    }

    // Upstream (not Flutter's default of downstream): at a boundary between
    // an RTL run and an embedded LTR run, a single logical offset can map
    // to two different visual x-positions. Upstream ties the caret to the
    // end of the run BEFORE this offset, which is the expected placement
    // for a cursor that just typed or moved past a character, rather than
    // splitting through the middle of the next run's first glyph.
    //
    // STILL OPEN (investigated again 2026-07-14, headlessly this time —
    // see caret_bidi_test.dart's multi-run case): confirmed the caret does
    // jump around inside a long Hebrew paragraph with an embedded English
    // clause + date, e.g. "...talking about - 20.4.26, למשל...". But it's
    // genuinely unclear how much of that is a bug versus inherent bidi
    // caret ambiguity that other editors also show at run boundaries — the
    // already-passing two-run test in this same file asserts the *exact
    // same kind of jump* (caret at a Hebrew/Latin seam sitting next to the
    // preceding run, not the following one) as *correct*, and that
    // reasoning generalizes to most of what shows up in the longer
    // sentence too. One offset (right after the trailing comma in
    // "20.4.26,", moving into the next Hebrew word) resolves inconsistently
    // with that same rule and looks like a real anomaly, but confirming
    // that needs either a reference implementation to compare against or a
    // human looking at it — not something to guess at blind. Tried
    // resolving position per-character via `getBoxesForSelection` instead
    // of `TextAffinity`; it produced byte-identical output to the
    // affinity-based approach at every offset tested, so the issue sits
    // deeper than either approach reaches (in Flutter's own bidi run
    // classification of weak/neutral characters like the comma), not in
    // this wrapper. Left as `TextAffinity.upstream` — the previously
    // validated fix for the simple case — pending a product decision on
    // what "correct" should mean here.
    final textPosition = TextPosition(
      offset: position.offset,
      affinity: TextAffinity.upstream,
    );
    double? placeholderCursorHeight =
        _placeholderRenderParagraph?.getFullHeightForCaret(textPosition);
    Offset? placeholderCursorOffset =
        _placeholderRenderParagraph?.getOffsetForCaret(
              textPosition,
              Rect.zero,
            ) ??
            Offset.zero;
    if (textDirection() == TextDirection.rtl && delta?.isEmpty == true) {
      // Empty RTL line: pin the caret to the line's RTL start — the RIGHT
      // edge of the placeholder paragraph — where Hebrew/Arabic typing
      // actually begins.
      //
      // Why this is needed: when the document default direction is RTL, an
      // empty line shows the LTR English hint ("Type '/' to insert a
      // block, or start typing"). That hint is a left-to-right run, so its
      // logical offset 0 resolves to the run's LEFT end. getOffsetForCaret
      // therefore returns the far-left of the (right-aligned) placeholder,
      // stranding the caret a whole placeholder-width to the left of where
      // the user starts typing — the reported "creating a new line has a
      // very far cursor" bug.
      //
      // The placeholder paragraph is right-aligned within the block, so
      // its own laid-out width is exactly the offset from the caret's
      // current (left) position to the RTL start (right). SET the caret's
      // dx to that width. Verified live on the real macOS app (the
      // headless test font + the shrink-wrapped block geometry make
      // selectionRects() mis-report this, so trust the rendered Cursor /
      // a live look — see document_rtl_empty_caret_test.dart).
      //
      // History: the previous code tried to shift by a "contentWidth" but
      // read `_renderParagraph?.size.width` first, which is a real,
      // non-null 0.0 for empty text, so the `??` never reached the
      // placeholder width and the whole correction was a permanent no-op.
      final placeholderWidth = _placeholderRenderParagraph?.size.width;
      if (placeholderWidth != null) {
        placeholderCursorOffset =
            Offset(placeholderWidth, placeholderCursorOffset.dy);
      }
    }

    double? cursorHeight =
        _renderParagraph?.getFullHeightForCaret(textPosition);
    Offset? cursorOffset =
        _renderParagraph?.getOffsetForCaret(textPosition, Rect.zero) ??
            Offset.zero;

    // Soft-wrap disambiguation (2026-07-20, generalised 2026-07-25): the
    // block-wide upstream affinity above is the validated choice for bidi run
    // seams WITHIN a line, but at a soft line-wrap boundary upstream and
    // downstream resolve to different LINES, and the offset alone cannot say
    // which one the user meant.
    //
    // The rule is: **put the caret on the line the pointer was actually on.**
    // Both candidate lines are laid out here, so their vertical bands are
    // known; the click's own dy picks the winner. This deliberately replaces
    // the earlier "honor a downstream affinity hint" rule, which fixed one
    // direction and caused the other: clicking the END of a wrapped line
    // reported `downstream` and threw the caret to the START of the next line
    // (reported 2026-07-25). Affinity is a claim about text; the pointer
    // position is the evidence.
    //
    // The `> 0.1` different-line guard is load-bearing and unchanged: when
    // both candidates sit on the SAME line (a bidi run seam — same line,
    // different x) this whole branch is skipped and the validated upstream
    // behaviour stands, which is what keeps the deferred embedded-date caret
    // question untouched.
    if (position is _AffinityHintPosition && delta?.isNotEmpty == true) {
      final downstreamTextPosition = TextPosition(offset: position.offset);
      final downstreamOffset = _renderParagraph?.getOffsetForCaret(
        downstreamTextPosition,
        Rect.zero,
      );
      if (downstreamOffset != null &&
          (downstreamOffset.dy - cursorOffset.dy).abs() > 0.1) {
        final downstreamHeight =
            _renderParagraph?.getFullHeightForCaret(downstreamTextPosition);
        final clickedDy = position.hitTestLocalOffset?.dy;

        final bool preferDownstream;
        if (clickedDy != null) {
          preferDownstream = _verticalDistanceToLine(
                clickedDy,
                downstreamOffset.dy,
                downstreamHeight ?? cursorHeight ?? 0,
              ) <
              _verticalDistanceToLine(
                clickedDy,
                cursorOffset.dy,
                cursorHeight ?? 0,
              );
        } else {
          // No recorded pointer position (not a hit-test-derived position):
          // fall back to the pre-2026-07-25 affinity rule.
          preferDownstream =
              position.hitTestAffinity == TextAffinity.downstream;
        }

        if (preferDownstream) {
          cursorOffset = downstreamOffset;
          cursorHeight = downstreamHeight ?? cursorHeight;
        }
      }
    }

    // Visual caret movement (2026-07-28) — see specs/bidi-caret-movement.md.
    //
    // At a directional boundary one offset has two homes on the same line, and
    // the block-wide upstream affinity above picks one of them arbitrarily. A
    // position produced by visual movement has already measured which home the
    // caret is in, so honour it.
    //
    // Deliberately a SEPARATE branch from the pointer hint above, rather than
    // relaxing that branch's `> 0.1` different-line guard. That guard is
    // load-bearing: it is what keeps the validated same-line seam behaviour —
    // and the deferred embedded-date question — untouched. Only positions this
    // editor's own movement created reach here, so no existing path changes.
    //
    // Both axes: a word/line jump can land the caret exactly AT a soft-wrap
    // boundary offset, which — like the pointer-hint branch above — has two
    // homes on different LINES, not just two x's on the same one. Upstream
    // affinity always resolves such an offset to the END of the line ABOVE;
    // the traversal that produced this position already measured which line
    // it actually crossed INTO, and dropping that y (originally "horizontal
    // only" because the common case is a same-line directional seam) sent
    // the caret to the previous line's end whenever a jump landed on such a
    // boundary — reported 2026-08-05: Option+Right from the end of "האזרח"
    // to jump back one word, when that word's start happened to be a
    // wrapped line's first offset, drew the caret at the END of the line
    // ABOVE (next to the previous word) instead of at "האזרח" itself, even
    // though the underlying offset was already correct.
    if (position is VisualCaretPosition && delta?.isNotEmpty == true) {
      cursorOffset = position.visualLocalOffset;
    }

    if (placeholderCursorHeight != null) {
      cursorHeight = max(cursorHeight ?? 0, placeholderCursorHeight);
    }

    if (delta?.isEmpty == true) {
      cursorOffset = placeholderCursorOffset;
    }

    if (widget.cursorHeight != null && cursorHeight != null) {
      cursorOffset = Offset(
        cursorOffset.dx,
        cursorOffset.dy + (cursorHeight - widget.cursorHeight!) / 2,
      );
      cursorHeight = widget.cursorHeight;
    }
    final rect = Rect.fromLTWH(
      max(0, cursorOffset.dx - (widget.cursorWidth / 2.0)),
      cursorOffset.dy,
      widget.cursorWidth,
      cursorHeight ?? 16.0,
    );
    return rect;
  }

  @override
  Position getPositionInOffset(Offset start) {
    final offset = _renderParagraph?.globalToLocal(start) ?? Offset.zero;
    final textPosition = _renderParagraph?.getPositionForOffset(offset);
    if (textPosition == null) {
      return Position(path: widget.node.path, offset: -1);
    }
    // Keep the affinity Flutter resolved for the tap, not just the integer
    // offset. At a soft line-wrap the offset alone is ambiguous — the same
    // integer is both "end of the previous visual line" and "start of this
    // one" — and only the affinity says which line was actually clicked.
    // getCursorRectInPosition uses it to keep the caret on that line.
    return _AffinityHintPosition(
      path: widget.node.path,
      offset: textPosition.offset,
      hitTestAffinity: textPosition.affinity,
      hitTestLocalOffset: offset,
    );
  }

  @override
  Selection? getWordEdgeInOffset(Offset offset) {
    final localOffset = _renderParagraph?.globalToLocal(offset) ?? Offset.zero;
    final textPosition = _renderParagraph?.getPositionForOffset(localOffset) ??
        const TextPosition(offset: 0);
    final textRange =
        _renderParagraph?.getWordBoundary(textPosition) ?? TextRange.empty;
    final wordEdgeOffset = textPosition.offset <= textRange.start
        ? textRange.start
        : textRange.end;

    return Selection.collapsed(
      Position(path: widget.node.path, offset: wordEdgeOffset),
    );
  }

  @override
  Selection? getWordBoundaryInOffset(Offset offset) {
    final localOffset = _renderParagraph?.globalToLocal(offset) ?? Offset.zero;
    final textPosition = _renderParagraph?.getPositionForOffset(localOffset) ??
        const TextPosition(offset: 0);
    final textRange =
        _renderParagraph?.getWordBoundary(textPosition) ?? TextRange.empty;
    final start = Position(path: widget.node.path, offset: textRange.start);
    final end = Position(path: widget.node.path, offset: textRange.end);
    return Selection(start: start, end: end);
  }

  @override
  Selection? getWordBoundaryInPosition(Position position) {
    final textPosition = TextPosition(offset: position.offset);
    final textRange =
        _renderParagraph?.getWordBoundary(textPosition) ?? TextRange.empty;
    final start = Position(path: widget.node.path, offset: textRange.start);
    final end = Position(path: widget.node.path, offset: textRange.end);
    return Selection(start: start, end: end);
  }

  @override
  Position? getNextVisualCaretPosition(
    Position position, {
    required bool towardsLeft,
    bool byWord = false,
    bool toLineEdge = false,
  }) {
    final paragraph = _renderParagraph;
    final text = widget.node.delta?.toPlainText();
    if (paragraph == null) {
      return null;
    }
    if (kDebugMode && paragraph.debugNeedsLayout) {
      return null;
    }
    if (text == null || text.isEmpty) {
      return null;
    }
    if (position.offset < 0 || position.offset > text.length) {
      return null;
    }

    // Where the caret is now. If it arrived here by visual movement it already
    // carries its x — and at a directional boundary that is the ONLY thing that
    // says which of the two homes it occupies, so it must be preferred over
    // re-deriving from the offset.
    final caretOffset = paragraph.getOffsetForCaret(
      TextPosition(offset: position.offset, affinity: TextAffinity.upstream),
      Rect.zero,
    );
    final currentX = position is VisualCaretPosition
        ? position.visualLocalOffset.dx
        : caretOffset.dx;
    final currentY = position is VisualCaretPosition
        ? position.visualLocalOffset.dy
        : caretOffset.dy;

    // The per-character boxes of the caret's OWN visual line, each kept with
    // its character offset.
    //
    // ⚠️ Scoped to the line on purpose. Measuring the whole block cost ~3.5µs
    // per character of it, on EVERY arrow press: 14ms on a 4,000-character
    // paragraph, which is a whole frame's budget spent before the editor does
    // anything else, and it is why a pasted page felt like treacle and the
    // keyboard stalled under key repeat (reported and measured 2026-07-29). A
    // visual line is bounded by the page width, so this is flat in the length
    // of the block.
    //
    // Two things this must NOT assume, both learned by instrumenting the
    // running app (2026-07-28):
    //
    // 1. That a line is a contiguous run of offsets. Characters consumed by a
    //    soft wrap return no box at all, so `firstOffset + i` mis-numbers every
    //    box after the first gap.
    // 2. That the caret's dy equals a glyph box's top. It does not: the editor
    //    applies a line-height multiplier, so the caret sits above the glyph
    //    box — measured at dy=-0.40 against boxes on a different y.
    final lines = <VisualLine>[];
    final seenLineTops = <int>{};

    TextBox? boxAt(int offset) {
      if (offset < 0 || offset >= text.length) return null;
      final charBoxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      );
      return charBoxes.isEmpty ? null : charBoxes.first;
    }

    /// Measures the visual line the character at [seed] is drawn on and appends
    /// it, or returns false when there is none (past either end of the text, or
    /// a line already measured).
    ///
    /// The line is found by growing outward from [seed] while the glyph boxes
    /// stay on the same row, which works because a soft wrap splits the text at
    /// a LOGICAL point: a visual line is always a contiguous range of offsets,
    /// however its runs are visually reordered inside it.
    ///
    /// ⚠️ Deliberately NOT `getLineBoundaryInPosition`, which was tried first
    /// and is wrong here. That helper finds a line by hit-testing its two
    /// horizontal extremes — correct in one-directional text, but in a mixed
    /// line the leftmost and rightmost glyphs are in the MIDDLE of the logical
    /// range. On the repro sentence it reported the line as offsets 39..47
    /// instead of 39..79, and leftward movement through the embedded English
    /// jumped from its end to its start (caught by the 158-step walk, which is
    /// why that harness exists).
    bool addLineFrom(int seed) {
      final seedBox = boxAt(seed);
      if (seedBox == null) return false;
      final top = seedBox.top;
      if (!seenLineTops.add((top * 10).round())) return false;

      final boxes = <TextBox>[seedBox];
      final offsets = <int>[seed];
      for (var i = seed - 1; i >= 0; i--) {
        final box = boxAt(i);
        if (box == null ||
            (box.top - top).abs() > VisualCaretTraversal.lineEpsilon) {
          break;
        }
        boxes.insert(0, box);
        offsets.insert(0, i);
      }
      for (var i = seed + 1; i < text.length; i++) {
        final box = boxAt(i);
        if (box == null ||
            (box.top - top).abs() > VisualCaretTraversal.lineEpsilon) {
          break;
        }
        boxes.add(box);
        offsets.add(i);
      }
      lines.add(VisualLine(top: top, boxes: boxes, offsets: offsets));
      lines.sort((a, b) => a.top.compareTo(b.top));
      return true;
    }

    // The caret's offset sits BETWEEN two characters, and at a soft wrap those
    // two are on different lines, so seed from both and let the caret's own y
    // pick the winner below.
    addLineFrom(position.offset);
    addLineFrom(position.offset - 1);
    if (lines.isEmpty) {
      return null;
    }

    // The y the RENDERER draws a caret at, per line — asked of the paragraph
    // rather than derived from the glyph boxes.
    //
    // ⚠️ This replaces a "nearest vertical band" match that was WRONG for every
    // line but the first (measured 2026-07-29 on a real macOS window). Glyph
    // bands abut to the pixel — line 1 spans y=21.0..45.0 and the caret on
    // line 2 sits at y=44.6 — so the caret on line N always fell inside line
    // N-1's band and was attributed to it. The visible result was a caret that
    // teleported to the paragraph's first line: in plain English, pressing
    // right at the end of visual line 1 jumped from offset 45 to offset 1.
    // That, not anything about bidi, is what "one left arrow lands in the
    // previous paragraph" was.
    //
    // Using `offsets.last` is what makes this unambiguous: a line's LAST offset
    // is always native to that line, while its first is the soft-wrap boundary
    // shared with the line above and resolves either way depending on affinity.
    double caretYOf(VisualLine line) => paragraph
        .getOffsetForCaret(
          TextPosition(
            offset: line.offsets.last,
            affinity: TextAffinity.upstream,
          ),
          Rect.zero,
        )
        .dy;
    final caretYs = <VisualLine, double>{};
    double caretY(int index) =>
        caretYs.putIfAbsent(lines[index], () => caretYOf(lines[index]));

    var lineIndex = 0;
    var bestDistance = (caretY(0) - currentY).abs();
    for (var i = 1; i < lines.length; i++) {
      final distance = (caretY(i) - currentY).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        lineIndex = i;
      }
    }

    final paragraphIsRtl = textDirection() == TextDirection.rtl;

    /// The offset a stop at [stop] on [line] resolves to, for LANDING
    /// purposes — as opposed to [VisualCaretTraversal.restingOffset], which
    /// always defers to the paragraph's own direction.
    ///
    /// At a directional boundary [VisualCaretTraversal.sidesAt] returns TWO
    /// different offsets for the same x — one per side — and for a character
    /// step the paragraph's side is the right tiebreak. For a WORD step it is
    /// not: [stopsOnLine] below keeps a stop specifically because one
    /// particular side satisfies the word predicate, and the landing offset
    /// must be THAT side, not whichever the paragraph happens to be.
    ///
    /// Measured consequence of getting this wrong (2026-08-05): from the end
    /// of "polites" in "…(spoudaios polites)?", stepping left with
    /// Option+Left correctly reached the start of "polites" (byWord kept the
    /// stop via its LTR side), but the NEXT Option+Left — now leftward past
    /// "polites" own start, where the stop's LTR side is "spoudaios"'s start
    /// but its RTL side is "polites"'s own end again — landed back on
    /// "polites"'s end because this always used the RTL (paragraph) side.
    /// The caret ping-ponged on one word instead of reaching "spoudaios".
    int? offsetForStop(VisualLine line, double stop) {
      if (!byWord) {
        return VisualCaretTraversal.restingOffset(
          line.boxes,
          stop,
          paragraphDirection: textDirection(),
          offsets: line.offsets,
        );
      }
      final sides = VisualCaretTraversal.sidesAt(
        line.boxes,
        stop,
        offsets: line.offsets,
      );
      final rtlSide = sides.rtl;
      final ltrSide = sides.ltr;
      // Unlike the non-byWord branch above, finding neither side valid here
      // means this stop is NOT a word edge at all, and must return null so
      // the caller (stopsOnLine's filter) rejects it — that rejection is
      // what makes a word jump skip character-level stops in the first
      // place. Silently falling back to the paragraph's side here is
      // exactly the bug this function exists to fix: it would readmit
      // every stop stopsOnLine meant to filter out.
      if (paragraphIsRtl) {
        // Word-start first, exactly as before — this priority is what keeps
        // a word jump landing on the semantically right side of an ambiguous
        // stop (a mirrored punctuation glyph like ")" can satisfy the
        // broader isSegmentStart check below on BOTH sides at once, which
        // regressed the polites/spoudaios fix above when tried first here).
        if (rtlSide != null && VisualCaretTraversal.isWordStart(text, rtlSide)) {
          return rtlSide;
        }
        if (ltrSide != null && VisualCaretTraversal.isWordStart(text, ltrSide)) {
          return ltrSide;
        }
        // Falls back to a punctuation run's own start only when neither side
        // is a word start at all, so Option+arrow stops before "," rather
        // than skipping straight to the next word (reported 2026-08-05).
        // Plain whitespace still gets no stop — the "skip the lone space"
        // rule is unchanged.
        if (rtlSide != null &&
            VisualCaretTraversal.isSegmentStart(text, rtlSide)) {
          return rtlSide;
        }
        if (ltrSide != null &&
            VisualCaretTraversal.isSegmentStart(text, ltrSide)) {
          return ltrSide;
        }
      } else {
        if (rtlSide != null &&
            VisualCaretTraversal.isWordBoundary(text, rtlSide)) {
          return rtlSide;
        }
        if (ltrSide != null &&
            VisualCaretTraversal.isWordBoundary(text, ltrSide)) {
          return ltrSide;
        }
      }
      return null;
    }

    /// The caret stops of line [index] that the renderer would actually draw ON
    /// that line.
    ///
    /// The filter matters at a soft wrap: the boundary offset has two homes —
    /// the end of the line above and the start of this one — and the renderer
    /// resolves it upstream, i.e. to the line above. Offering its start-of-line
    /// home as a stop here produced a caret drawn with THIS line's x at the
    /// PREVIOUS line's y: pressing left from the start of a wrapped line put
    /// the caret at the paragraph's top-left corner. Dropping it means that
    /// place is reached by crossing the line, which is what the reader means by
    /// it anyway.
    List<double> stopsOnLine(int index) {
      final line = lines[index];
      final lineCaretY = caretY(index);
      return VisualCaretTraversal.stopsFor(line.boxes).where((stop) {
        final resting = offsetForStop(line, stop);
        if (resting == null) {
          return false;
        }
        final drawnY = paragraph
            .getOffsetForCaret(
              TextPosition(offset: resting, affinity: TextAffinity.upstream),
              Rect.zero,
            )
            .dy;
        return (drawnY - lineCaretY).abs() <= VisualCaretTraversal.lineEpsilon;
      }).toList();
    }

    var landingLine = lineIndex;
    double? nextX;
    final stops = stopsOnLine(lineIndex);
    if (toLineEdge) {
      if (stops.isNotEmpty) {
        final edge = towardsLeft ? stops.first : stops.last;
        nextX = (edge - currentX).abs() <= VisualCaretTraversal.epsilon
            ? null
            : edge;
      }
    } else {
      nextX = VisualCaretTraversal.step(
        stops,
        currentX,
        towardsLeft: towardsLeft,
      );

      if (nextX == null) {
        // The line's visual edge. Cross to the neighbouring line HERE rather
        // than returning null and letting offset arithmetic guess: the caret's
        // place on the line is measured, and the arithmetic has no way to know
        // it, so the two disagree at exactly the boundary the reader is
        // crossing.
        //
        // Which line is next depends on the paragraph, not on the key: reading
        // an RTL paragraph moves LEFTWARD, so running off the left edge of a
        // line continues on the line BELOW, while in an LTR paragraph it
        // continues on the line ABOVE. Either way the caret arrives at the far
        // side — leftward movement lands on the target line's rightmost stop —
        // which is what wrapping around a line looks like.
        //
        // Neighbouring lines are measured one at a time, and only when the
        // caret actually reaches an edge, so the ordinary keypress in the
        // middle of a line still measures exactly one line.
        final step = towardsLeft
            ? (paragraphIsRtl ? 1 : -1)
            : (paragraphIsRtl ? -1 : 1);
        var i = lineIndex + step;
        while (true) {
          if (i < 0 || i >= lines.length) {
            // Reach one line further out, past whichever end of the measured
            // set we are at. Because a line is a contiguous range of offsets,
            // the character just outside it belongs to the neighbouring line.
            final edgeLine = i < 0 ? lines.first : lines.last;
            final seed = i < 0
                ? edgeLine.offsets.first - 1
                : edgeLine.offsets.last + 1;
            final grew = addLineFrom(seed);
            if (!grew) break;
            // groupIntoLines keeps `lines` sorted by top, so a line added above
            // shifts every index down by one.
            if (i < 0) {
              i = 0;
              lineIndex += 1;
              landingLine += 1;
            }
            continue;
          }
          // A word jump can find no stop at all on a line it passes over, so
          // keep going rather than stalling there.
          final candidates = stopsOnLine(i);
          if (candidates.isNotEmpty) {
            nextX = towardsLeft ? candidates.last : candidates.first;
            landingLine = i;
            break;
          }
          i += step;
        }
      }
    }

    // Still null means the block's own visual edge: the caller crosses to the
    // neighbouring block using the behaviour it already has.
    if (nextX == null) {
      return null;
    }

    final offset = offsetForStop(lines[landingLine], nextX);
    if (offset == null) {
      return null;
    }

    return VisualCaretPosition(
      path: widget.node.path,
      offset: offset,
      visualLocalOffset: Offset(nextX, caretY(landingLine)),
    );
  }

  @override
  Selection? getLineBoundaryInPosition(Position position) {
    final delta = widget.node.delta;
    if (position.offset < 0 ||
        (delta != null && position.offset > delta.length)) {
      return null;
    }
    final paragraph = _renderParagraph;
    if (paragraph == null || (kDebugMode && paragraph.debugNeedsLayout)) {
      return null;
    }
    // Resolve the position with the same affinity the caret renderer uses
    // (upstream by default, downstream when a pointer hit-test hint says
    // so — see getCursorRectInPosition), so at a soft-wrap boundary the
    // returned line is the one the user actually sees the caret on.
    var affinity = TextAffinity.upstream;
    if (position is _AffinityHintPosition &&
        position.hitTestAffinity == TextAffinity.downstream) {
      affinity = TextAffinity.downstream;
    }
    final textPosition =
        TextPosition(offset: position.offset, affinity: affinity);

    // RenderParagraph exposes no public getLineBoundary (it is private,
    // `_getLineAtOffset`, as of Flutter 3.27), so derive the visual line's
    // span by hit-testing just past the line's two horizontal edges — the
    // same semantics a click at either edge has: the leading edge resolves
    // to the line's first position, the trailing edge to its last,
    // whichever side each is on in the paragraph's direction. min/max
    // makes it direction-agnostic.
    final caretTop = paragraph.getOffsetForCaret(textPosition, Rect.zero).dy;
    final lineMidY =
        caretTop + paragraph.getFullHeightForCaret(textPosition) / 2;
    final a = paragraph.getPositionForOffset(Offset(-10, lineMidY)).offset;
    final b = paragraph
        .getPositionForOffset(Offset(paragraph.size.width + 10, lineMidY))
        .offset;
    return Selection(
      start: Position(path: widget.node.path, offset: min(a, b)),
      end: Position(path: widget.node.path, offset: max(a, b)),
    );
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
    RenderParagraph? paragraph,
  }) {
    paragraph ??= _renderParagraph;
    if (kDebugMode && paragraph?.debugNeedsLayout == true) {
      return [];
    }
    final textSelection = textSelectionFromEditorSelection(selection);
    if (textSelection == null) {
      return [];
    }
    final rects = paragraph
        ?.getBoxesForSelection(
          textSelection,
          boxHeightStyle: BoxHeightStyle.max,
        )
        .map((box) => box.toRect())
        .toList(growable: false);
    if (rects == null || rects.isEmpty) {
      /// If the rich text widget does not contain any text,
      /// there will be no selection boxes,
      /// so we need to return to the default selection.
      Offset position = Offset.zero;
      double height = paragraph?.size.height ?? 0.0;
      double width = 0;
      if (!selection.isCollapsed) {
        /// while selecting for an empty character, return a selection area
        /// with width of 2
        final textPosition = TextPosition(offset: textSelection.baseOffset);
        position = paragraph?.getOffsetForCaret(
              textPosition,
              Rect.zero,
            ) ??
            position;
        height = paragraph?.getFullHeightForCaret(textPosition) ?? height;
        width = 2;
      }
      return [
        Rect.fromLTWH(position.dx, position.dy, width, height),
      ];
    }
    return rects;
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) {
    final delta = widget.node.delta;
    if (delta == null) {
      return Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 0,
      );
    }
    final localStart = _renderParagraph?.globalToLocal(start) ?? Offset.zero;
    final localEnd = _renderParagraph?.globalToLocal(end) ?? Offset.zero;
    final baseOffset =
        _renderParagraph?.getPositionForOffset(localStart).offset ?? -1;
    final extentOffset =
        _renderParagraph?.getPositionForOffset(localEnd).offset ?? -1;
    return Selection.single(
      path: widget.node.path,
      startOffset: baseOffset,
      endOffset: extentOffset,
    );
  }

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) {
    return _renderParagraph?.localToGlobal(offset) ?? Offset.zero;
  }

  @override
  TextDirection textDirection() {
    return widget.textDirection;
  }

  Widget _buildPlaceholderText(BuildContext context) {
    var textSpan = getPlaceholderTextSpan();
    if (widget.placeholderTextSpanDecorator != null) {
      textSpan = widget.placeholderTextSpanDecorator!(textSpan);
    }
    textSpan = adjustTextSpan(textSpan);
    final delta = widget.node.delta;
    if (delta != null && delta.isNotEmpty) {
      // The line has real text, so the placeholder isn't shown. Collapse it to
      // an empty span (keeping the style for line height) instead of merely
      // making it transparent: a full-width invisible placeholder still
      // inflates the block to its own width, which on a right-aligned RTL
      // block pushes the real text a placeholder-width LEFT of the content-area
      // right edge — the "text jumps left the moment you type" bug. An empty
      // span keeps the placeholder render object (and its height) but takes no
      // width, so the RTL text stays pinned to the right.
      textSpan = TextSpan(text: '', style: textSpan.style);
    }
    return RichText(
      key: placeholderTextKey,
      textHeightBehavior: TextHeightBehavior(
        applyHeightToFirstAscent:
            textStyleConfiguration.applyHeightToFirstAscent,
        applyHeightToLastDescent:
            textStyleConfiguration.applyHeightToLastDescent,
        leadingDistribution: textStyleConfiguration.leadingDistribution,
      ),
      text: textSpan,
      textDirection: textDirection(),
      textScaler: TextScaler.linear(
        widget.editorState.editorStyle.textScaleFactor,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildRichText(BuildContext context) {
    final textInserts = widget.node.delta!.whereType<TextInsert>();
    TextSpan textSpan = getTextSpan(textInserts: textInserts);
    if (widget.textSpanDecorator != null) {
      textSpan = widget.textSpanDecorator!(textSpan);
    }
    textSpan = adjustTextSpan(textSpan);
    return RichText(
      key: textKey,
      textAlign: widget.textAlign ?? TextAlign.start,
      textHeightBehavior: TextHeightBehavior(
        applyHeightToFirstAscent:
            textStyleConfiguration.applyHeightToFirstAscent,
        applyHeightToLastDescent:
            textStyleConfiguration.applyHeightToLastDescent,
        leadingDistribution: textStyleConfiguration.leadingDistribution,
      ),
      text: textSpan,
      textDirection: textDirection(),
      textScaler:
          TextScaler.linear(widget.editorState.editorStyle.textScaleFactor),
    );
  }

  List<Widget> _buildRichTextOverlay(BuildContext context) {
    if (textKey.currentContext == null) return [];
    return textSpanOverlayBuilder?.call(
          context,
          widget.node,
          this,
        ) ??
        [];
  }

  void confirmContextEnabled() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && textKey.currentContext == null) {
        confirmContextEnabled();
      } else if (mounted && textKey.currentContext != null) {
        setState(() {});
      }
    });
  }

  Widget _buildAutoCompleteRichText() {
    final textInserts = widget.node.delta!.whereType<TextInsert>();
    TextSpan textSpan = getTextSpan(textInserts: textInserts);
    if (widget.textSpanDecorator != null) {
      textSpan = widget.textSpanDecorator!(textSpan);
    }
    textSpan = adjustTextSpan(textSpan);
    return ValueListenableBuilder(
      valueListenable: widget.editorState.selectionNotifier,
      builder: (_, __, ___) {
        final autoCompleteText = autoCompleteTextProvider?.call(
          context,
          widget.node,
          textSpan,
        );
        if (autoCompleteText == null || autoCompleteText.isEmpty) {
          return const SizedBox.shrink();
        }
        textSpan = getTextSpan(
          textInserts: [
            ...textInserts.map(
              (e) => TextInsert(
                e.text,
                attributes: {
                  AppFlowyRichTextKeys.transparent: true,
                },
              ),
            ),
            TextInsert(
              autoCompleteText,
              attributes: {
                AppFlowyRichTextKeys.autoComplete: true,
              },
            ),
          ],
        );
        return RichText(
          textAlign: widget.textAlign ?? TextAlign.start,
          textHeightBehavior: TextHeightBehavior(
            applyHeightToFirstAscent:
                textStyleConfiguration.applyHeightToFirstAscent,
            applyHeightToLastDescent:
                textStyleConfiguration.applyHeightToLastDescent,
            leadingDistribution: textStyleConfiguration.leadingDistribution,
          ),
          text: textSpan,
          textDirection: textDirection(),
          textScaler:
              TextScaler.linear(widget.editorState.editorStyle.textScaleFactor),
        );
      },
    );
  }

  // https://github.com/flutter/flutter/pull/143954
  // https://github.com/AppFlowy-IO/appflowy-editor/issues/819#issuecomment-2177833413
  // This is a workaround for the issue that
  //  the caret height of the text is not calculated correctly if the parent style is null.
  TextSpan adjustTextSpan(TextSpan textSpan) {
    if (textSpan.style == null && textSpan.children != null) {
      double height = 0.0;
      double fontSize = 0.0;
      textSpan.visitChildren((span) {
        final style = span.style;
        if (style != null) {
          if (style.height != null) {
            height = max(height, style.height!);
          }
          if (style.fontSize != null) {
            fontSize = max(fontSize, style.fontSize!);
          }
        }
        return true;
      });
      if (height == 0.0 || fontSize == 0.0) {
        return textSpan;
      }
      textSpan = textSpan.copyWith(
        style: textStyleConfiguration.text.copyWith(
          height: height,
          fontSize: fontSize,
        ),
      );
    }
    return textSpan;
  }

  TextSpan getPlaceholderTextSpan() {
    return TextSpan(
      children: [
        TextSpan(
          text: widget.placeholderText,
          style: textStyleConfiguration.text.copyWith(
            height: textStyleConfiguration.lineHeight,
          ),
        ),
      ],
    );
  }

  TextSpan getTextSpan({
    required Iterable<TextInsert> textInserts,
  }) {
    int offset = 0;
    List<InlineSpan> textSpans = [];
    for (final textInsert in textInserts) {
      TextStyle textStyle = textStyleConfiguration.text.copyWith(
        height: textStyleConfiguration.lineHeight,
      );
      final attributes = textInsert.attributes;
      if (attributes != null) {
        if (attributes.bold == true) {
          textStyle = textStyle.combine(textStyleConfiguration.bold);
        }
        if (attributes.italic == true) {
          textStyle = textStyle.combine(textStyleConfiguration.italic);
        }
        if (attributes.underline == true) {
          textStyle = textStyle.combine(textStyleConfiguration.underline);
        }
        if (attributes.strikethrough == true) {
          textStyle = textStyle.combine(textStyleConfiguration.strikethrough);
        }
        if (attributes.href != null) {
          textStyle = textStyle.combine(textStyleConfiguration.href);
        }
        if (attributes.code == true) {
          textStyle = textStyle.combine(textStyleConfiguration.code);
        }
        if (attributes.backgroundColor != null) {
          textStyle = textStyle.combine(
            TextStyle(backgroundColor: attributes.backgroundColor),
          );
        }
        if (attributes.findBackgroundColor != null) {
          textStyle = textStyle.combine(
            TextStyle(backgroundColor: attributes.findBackgroundColor),
          );
        }
        if (attributes.color != null) {
          textStyle = textStyle.combine(
            TextStyle(color: attributes.color),
          );
        }
        if (attributes.fontFamily != null) {
          textStyle = textStyle.combine(
            TextStyle(fontFamily: attributes.fontFamily),
          );
        }
        if (attributes.fontSize != null) {
          textStyle = textStyle.combine(
            TextStyle(fontSize: attributes.fontSize),
          );
        }
        // [fork:ribbon] Phase 4 — super/subscript via OpenType font features.
        // These stay pure TextSpans, so the caret and selection map 1:1 to
        // characters (a WidgetSpan would collapse the run to one placeholder).
        // Write-time mutual exclusivity means both are never set at once.
        if (attributes.superscript == true) {
          textStyle = textStyle.combine(
            const TextStyle(fontFeatures: [FontFeature.superscripts()]),
          );
        }
        if (attributes.subscript == true) {
          textStyle = textStyle.combine(
            const TextStyle(fontFeatures: [FontFeature.subscripts()]),
          );
        }
        if (attributes.autoComplete == true) {
          textStyle = textStyle.combine(textStyleConfiguration.autoComplete);
        }
        if (attributes.transparent == true) {
          textStyle = textStyle.combine(
            const TextStyle(color: Colors.transparent),
          );
        }
      }
      final textSpan = TextSpan(
        text: textInsert.text,
        style: textStyle,
      );
      textSpans.add(
        textSpanDecoratorForAttribute != null
            ? textSpanDecoratorForAttribute!(
                context,
                widget.node,
                offset,
                textInsert,
                textSpan,
                widget.textSpanDecorator?.call(textSpan) ?? textSpan,
              )
            : textSpan,
      );
      offset += textInsert.length;
    }
    return TextSpan(
      children: textSpans,
    );
  }

  TextSelection? textSelectionFromEditorSelection(Selection? selection) {
    if (selection == null) {
      return null;
    }

    final normalized = selection.normalized;
    final path = widget.node.path;
    if (path < normalized.start.path || path > normalized.end.path) {
      return null;
    }

    final length = widget.node.delta?.length;
    if (length == null) {
      return null;
    }

    TextSelection? textSelection;

    if (normalized.isSingle) {
      if (path.equals(normalized.start.path)) {
        if (normalized.isCollapsed) {
          textSelection = TextSelection.collapsed(
            offset: normalized.startIndex,
          );
        } else {
          textSelection = TextSelection(
            baseOffset: normalized.startIndex,
            extentOffset: normalized.endIndex,
          );
        }
      }
    } else {
      if (path.equals(normalized.start.path)) {
        textSelection = TextSelection(
          baseOffset: normalized.startIndex,
          extentOffset: length,
        );
      } else if (path.equals(normalized.end.path)) {
        textSelection = TextSelection(
          baseOffset: 0,
          extentOffset: normalized.endIndex,
        );
      } else {
        textSelection = TextSelection(
          baseOffset: 0,
          extentOffset: length,
        );
      }
    }
    return textSelection;
  }
}

extension AppFlowyRichTextAttributes on Attributes {
  bool get bold => this[AppFlowyRichTextKeys.bold] == true;

  bool get italic => this[AppFlowyRichTextKeys.italic] == true;

  bool get underline => this[AppFlowyRichTextKeys.underline] == true;

  bool get code => this[AppFlowyRichTextKeys.code] == true;

  bool get strikethrough {
    return (containsKey(AppFlowyRichTextKeys.strikethrough) &&
        this[AppFlowyRichTextKeys.strikethrough] == true);
  }

  Color? get color {
    final textColor = this[AppFlowyRichTextKeys.textColor] as String?;
    return textColor?.tryToColor();
  }

  Color? get backgroundColor {
    final highlightColor =
        this[AppFlowyRichTextKeys.backgroundColor] as String?;
    return highlightColor?.tryToColor();
  }

  Color? get findBackgroundColor {
    final findBackgroundColor =
        this[AppFlowyRichTextKeys.findBackgroundColor] as String?;
    return findBackgroundColor?.tryToColor();
  }

  String? get href {
    if (this[AppFlowyRichTextKeys.href] is String) {
      return this[AppFlowyRichTextKeys.href];
    }
    return null;
  }

  String? get fontFamily {
    if (this[AppFlowyRichTextKeys.fontFamily] is String) {
      return this[AppFlowyRichTextKeys.fontFamily];
    }
    return null;
  }

  double? get fontSize {
    if (this[AppFlowyRichTextKeys.fontSize] is double) {
      return this[AppFlowyRichTextKeys.fontSize];
    }
    return null;
  }

  bool get autoComplete => this[AppFlowyRichTextKeys.autoComplete] == true;

  bool get transparent => this[AppFlowyRichTextKeys.transparent] == true;

  bool get superscript => this[AppFlowyRichTextKeys.superscript] == true;

  bool get subscript => this[AppFlowyRichTextKeys.subscript] == true;
}

/// A [Position] that additionally remembers the [TextAffinity] a pointer
/// hit-test resolved to.
///
/// [Position] deliberately models only `path` + `offset`, which is one bit
/// short at a soft line-wrap: the wrap-boundary offset means both "end of
/// the previous visual line" and "start of the next", and dropping the
/// affinity made the caret renderer always pick the previous line — so in
/// RTL, clicking just right of a wrapped line visibly threw the caret to
/// the far LEFT of the line above (specs/rtl-support.md, reproduced live
/// 2026-07-20).
///
/// This is a display-only hint, not part of the model: equality, hashing
/// and JSON stay [Position]'s, and any `copyWith`/serialization round-trip
/// elsewhere in the editor silently degrades it back to a plain [Position]
/// (i.e. to the pre-hint caret placement) — never breaks. One known
/// consequence: two successive gutter clicks that resolve to the same
/// integer offset with different affinities compare equal, so the second
/// may not visibly move the caret; harmless, and fixing it would mean
/// putting affinity into Position's ==, which is a far riskier change.
/// How far [y] sits outside the vertical band of a line whose caret starts at
/// [lineTop] and is [lineHeight] tall. Returns 0 when [y] is inside the band,
/// so a click anywhere on a line is treated as unambiguously belonging to it.
///
/// Used to choose between the two candidate lines at a soft-wrap boundary; see
/// the call site in `getCursorRectInPosition`.
double _verticalDistanceToLine(double y, double lineTop, double lineHeight) {
  final lineBottom = lineTop + lineHeight;
  if (y < lineTop) {
    return lineTop - y;
  }
  if (y > lineBottom) {
    return y - lineBottom;
  }
  return 0;
}

/// Update 2026-07-25: the hint now also carries the pointer's own local
/// offset. Affinity alone turned out to be one bit short in the mirror case —
/// clicking at the END of a wrapped line put the caret at the START of the
/// next one, because Flutter reported `downstream` there and the renderer
/// dutifully followed it onto the wrong line. The pointer's y says which line
/// the user actually aimed at, and that is the thing being disambiguated, so
/// it is a better oracle than the affinity flag. Affinity remains the
/// fallback for the (rare) case where no local offset was recorded.
class _AffinityHintPosition extends Position {
  _AffinityHintPosition({
    required super.path,
    super.offset,
    required this.hitTestAffinity,
    this.hitTestLocalOffset,
  });

  final TextAffinity hitTestAffinity;

  /// Where the pointer landed, in the render paragraph's local coordinates.
  final Offset? hitTestLocalOffset;
}
