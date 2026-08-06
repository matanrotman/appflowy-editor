import 'package:flutter/rendering.dart';

/// Visual caret traversal for bidirectional text.
///
/// See `specs/bidi-caret-movement.md` in the Ludwig repo for the full
/// reasoning. The short version:
///
/// AppFlowy moves the caret with rune arithmetic and flips direction once per
/// BLOCK, so inside an English word embedded in a Hebrew paragraph the left
/// arrow travels rightward. The rule adopted to fix it (user decision,
/// 2026-07-28) **deliberately diverges from the Unicode bidi caret
/// convention**:
///
///  * **Movement follows the paragraph.** In an RTL paragraph the left arrow
///    always steps exactly one visual position leftward. It never reverses and
///    never switches sides in place, so an embedded `ABC` is walked C, B, A.
///  * **Typing follows the character.** See [insertionOffset].
///
/// Why this is expressed over [TextBox]es rather than over character offsets:
/// at a directional boundary one character offset has TWO homes on the line —
/// measured, not assumed: in `שלום ABC עולם` offsets 5 and 8 each resolve to
/// both x=38.97 and x=71.72 — so no function of the offset alone can say where
/// the caret is. A *visual stop* is unambiguous, and each one maps to one
/// offset per direction once the side is known.
class VisualCaretTraversal {
  const VisualCaretTraversal._();

  /// Tolerance for treating two measured coordinates as the same point. Text
  /// layout returns doubles that differ in their last bits for what is visually
  /// a single position.
  static const double epsilon = 0.5;

  /// Tolerance for deciding two glyph boxes share a visual line, and for
  /// matching a caret's y against a line's. Lines are ~20pt apart, so this is
  /// generous without ever merging two of them.
  static const double lineEpsilon = 0.1;

  /// Whether mouse clicks (single click, double-click word-select,
  /// drag-select, shift-click extend) resolve position via this same
  /// visual-stop model, instead of trusting Flutter's own bidi hit-testing
  /// (`getPositionForOffset`, `getWordBoundary`).
  ///
  /// ⚠️ An experiment behind a switch, per `specs/bidi-caret-movement.md`'s
  /// "Click positioning" scoping (session 24) in the Ludwig repo. Off keeps
  /// today's click behaviour exactly — including its known bug, where a click
  /// past a wrapped line's true end or past the page margin can resolve to an
  /// unrelated offset elsewhere in the paragraph. On resolves every click via
  /// the caret's own visual-line/visual-stop model instead.
  ///
  /// A previous attempt at a narrower fix (redirecting only the specific
  /// overshoot case) passed every automated test, including on the real
  /// macOS window, and still broke clicking broadly once shipped live — this
  /// flag exists so the wider fix can be compared against the old behaviour
  /// without that risk repeating.
  ///
  /// Set by the host app; the editor never persists it.
  static bool resolveClicksVisually = false;

  /// The glyph boxes of [boxes] grouped into visual lines, top-most first.
  ///
  /// `boxes[i]` is the box of the character at `offsets[i]`. Characters
  /// consumed by a soft wrap return no box at all, so the offsets are NOT
  /// assumed to be contiguous — assuming that mis-numbered every box after the
  /// first gap when this was first built (2026-07-28).
  static List<VisualLine> groupIntoLines(
    List<TextBox> boxes,
    List<int> offsets,
  ) {
    final lines = <VisualLine>[];
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      final line = lines.where((l) => (l.top - box.top).abs() <= lineEpsilon);
      if (line.isEmpty) {
        lines.add(VisualLine(top: box.top, boxes: [box], offsets: [offsets[i]]));
      } else {
        line.first.boxes.add(box);
        line.first.offsets.add(offsets[i]);
      }
    }
    lines.sort((a, b) => a.top.compareTo(b.top));
    return lines;
  }

  /// Every distinct caret position on [boxes], ordered visually left to right.
  ///
  /// [boxes] are the per-character boxes of ONE visual line, `boxes[i]` being
  /// the box of character `i` counting from [firstOffset]. Each box contributes
  /// both vertical edges — a caret can sit on either side of a glyph.
  static List<double> stopsFor(List<TextBox> boxes) {
    final edges = <double>[];
    for (final box in boxes) {
      edges
        ..add(box.left)
        ..add(box.right);
    }
    edges.sort();

    final stops = <double>[];
    for (final edge in edges) {
      if (stops.isEmpty || (edge - stops.last).abs() > epsilon) {
        stops.add(edge);
      }
    }
    return stops;
  }

  /// [stopsFor], with the OUTER edge of a trailing invisible line-wrap
  /// space removed — unless [isBlockFinalLine], where a trailing space is
  /// real content rather than a wrap artifact.
  ///
  /// A soft wrap's trailing whitespace still measures a real box even
  /// though nothing is drawn for it (the renderer just breaks the line
  /// after it), so [stopsFor] reports a caret stop past the last VISIBLE
  /// character — the caret can land in blank space nothing is drawn in.
  /// Measured 2026-08-06: at the wrap between "…לזו של" and "האזרח…", the
  /// space after "של" contributed two stops, one right after the ל (its
  /// INNER edge, bordering real content — kept) and one a further
  /// character-width to the left (its OUTER edge, bordering nothing on
  /// this line — the reported "falls one space too far"). The outer edge
  /// is dropped only when it borders no other box on the line, which is
  /// what makes it a wrap artifact rather than ordinary text.
  static List<double> stopsForLine(
    List<TextBox> boxes,
    List<int> offsets,
    String text, {
    required bool isBlockFinalLine,
  }) {
    final stops = stopsFor(boxes);
    if (isBlockFinalLine || boxes.isEmpty) return stops;
    final lastOffset = offsets.last;
    if (lastOffset < 0 || lastOffset >= text.length) return stops;
    if (text[lastOffset].trim().isNotEmpty) return stops;

    final trailingBox = boxes.last;
    bool bordersOtherBox(double edge) {
      for (var i = 0; i < boxes.length - 1; i++) {
        if ((boxes[i].left - edge).abs() <= epsilon ||
            (boxes[i].right - edge).abs() <= epsilon) {
          return true;
        }
      }
      return false;
    }

    final leftIsLonely = !bordersOtherBox(trailingBox.left);
    final rightIsLonely = !bordersOtherBox(trailingBox.right);
    double? outerEdge;
    if (leftIsLonely && !rightIsLonely) outerEdge = trailingBox.left;
    if (rightIsLonely && !leftIsLonely) outerEdge = trailingBox.right;
    if (outerEdge == null) return stops;

    return stops.where((s) => (s - outerEdge!).abs() > epsilon).toList();
  }

  /// The caret position one visual step from [currentX].
  ///
  /// Returns null at the line's visual edge — the caller's signal to cross into
  /// the neighbouring line or block, which the arrow commands already handle.
  static double? step(
    List<double> stops,
    double currentX, {
    required bool towardsLeft,
  }) {
    double? best;
    for (final stop in stops) {
      if (towardsLeft) {
        if (stop < currentX - epsilon && (best == null || stop > best)) {
          best = stop;
        }
      } else {
        if (stop > currentX + epsilon && (best == null || stop < best)) {
          best = stop;
        }
      }
    }
    return best;
  }

  /// The character offsets that share the visual stop at [x], one per
  /// direction.
  ///
  /// A stop inside a run has the same offset on both sides. A stop at a
  /// directional boundary has two different ones, and which is correct depends
  /// on the direction of whatever is about to be written there — hence
  /// [insertionOffset].
  ///
  /// `boxes[i]` must be the box of the character at offset `firstOffset + i`.
  /// Pass [offsets] when the boxes are not a contiguous run — `offsets[i]` is
  /// then the character offset of `boxes[i]`. Real wrapped text needs this:
  /// characters consumed by a soft wrap return no box at all, so assuming
  /// `firstOffset + i` silently mis-numbers every box after the first gap.
  static ({int? rtl, int? ltr}) sidesAt(
    List<TextBox> boxes,
    double x, {
    int firstOffset = 0,
    List<int>? offsets,
  }) {
    int? rtl;
    int? ltr;

    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      final isLtr = box.direction == TextDirection.ltr;
      final start = offsets != null ? offsets[i] : firstOffset + i;
      final end = start + 1;

      // For an LTR glyph the caret before it is at its left edge and the caret
      // after it at its right edge; for an RTL glyph the two are swapped.
      final touchesLeft = (box.left - x).abs() <= epsilon;
      final touchesRight = (box.right - x).abs() <= epsilon;
      if (!touchesLeft && !touchesRight) continue;

      final int offset;
      if (isLtr) {
        offset = touchesLeft ? start : end;
      } else {
        offset = touchesLeft ? end : start;
      }

      if (isLtr) {
        ltr ??= offset;
      } else {
        rtl ??= offset;
      }
    }

    // Inside a run only one direction is present; it answers for both.
    return (rtl: rtl ?? ltr, ltr: ltr ?? rtl);
  }

  /// Where [character] should be inserted when the caret sits at [x].
  ///
  /// **Typing follows the character**: a right-to-left character inserts on the
  /// RTL side, a left-to-right character on the LTR side, and a neutral
  /// character (space, digit, punctuation) falls back to [paragraphDirection].
  ///
  /// Measured consequence: with this rule the typed character appears exactly
  /// where the caret was drawn, in either language. Choosing the other side
  /// makes it jump across the embedded word.
  static int? insertionOffset(
    List<TextBox> boxes,
    double x,
    String character, {
    required TextDirection paragraphDirection,
    int firstOffset = 0,
  }) {
    final sides = sidesAt(boxes, x, firstOffset: firstOffset);
    final direction = directionOf(character) ?? paragraphDirection;
    return direction == TextDirection.rtl ? sides.rtl : sides.ltr;
  }

  /// The offset to store for a caret that has just moved to [x], before any
  /// character is typed.
  ///
  /// Defaults to the paragraph's own side, matching [insertionOffset]'s
  /// treatment of neutral characters, so that a caret which is moved and then
  /// used without typing behaves consistently.
  static int? restingOffset(
    List<TextBox> boxes,
    double x, {
    required TextDirection paragraphDirection,
    int firstOffset = 0,
    List<int>? offsets,
  }) {
    final sides = sidesAt(boxes, x, firstOffset: firstOffset, offsets: offsets);
    return paragraphDirection == TextDirection.rtl ? sides.rtl : sides.ltr;
  }

  /// Whether a caret sitting at character offset [offset] is at a WORD edge.
  ///
  /// Word jumps have to agree with visual movement or the two feel unrelated:
  /// the caret moves one visual step at a time, so a word jump must land on a
  /// visual stop that also happens to be a word edge — not on whatever offset
  /// logical word arithmetic produces, which in bidi text can be somewhere else
  /// on the line entirely. That mismatch is what made Option+arrow skip a lone
  /// space and then leap to the end of the sentence (reported 2026-07-28).
  static bool isWordBoundary(String text, int offset) {
    if (offset <= 0 || offset >= text.length) return true;
    final before = _isWordCharacter(text[offset - 1]);
    final after = _isWordCharacter(text[offset]);
    return before != after;
  }

  /// Whether [offset] is where a word BEGINS in its own reading direction.
  ///
  /// Word jumps land here rather than on every word edge, so a lone space is
  /// stepped over instead of being a stop of its own (user, 2026-07-28: "skip
  /// the lone space and start at the edge of the next word"). Because the caret
  /// for offset o sits at the LEFT edge of an LTR glyph and the RIGHT edge of an
  /// RTL one, "the offset where the word starts" already resolves to the right
  /// side for Hebrew and the left side for English — no direction test needed
  /// here.
  static bool isWordStart(String text, int offset) {
    if (offset < 0 || offset >= text.length) return false;
    if (!_isWordCharacter(text[offset])) return false;
    return offset == 0 || !_isWordCharacter(text[offset - 1]);
  }

  static bool _isWordCharacter(String character) {
    if (character.trim().isEmpty) return false;
    final code = character.runes.first;
    // Letters and digits count; punctuation does not, so "20.4.26," breaks into
    // pieces the way it visually reads.
    if (code >= 0x0030 && code <= 0x0039) return true;
    if (directionOf(character) != null) return true;
    return false;
  }

  /// Whether [offset] is where a non-whitespace SEGMENT begins — a word, or a
  /// run of punctuation — in an RTL paragraph's word-jump stops.
  ///
  /// [isWordStart] alone treats punctuation the same as whitespace (neither
  /// is a "word character"), so a comma got no stop of its own and a word
  /// jump skipped straight over it to the next word (reported 2026-08-05:
  /// from before "הקשר," Option+left should stop once right after קשר,
  /// before the comma, THEN at על — it jumped straight to על). Whitespace
  /// still gets no stop of its own — [isWordStart]'s "skip the lone space"
  /// rule (2026-07-28) is unchanged — but a punctuation run now does, the
  /// same way a word does.
  static bool isSegmentStart(String text, int offset) {
    if (offset < 0 || offset >= text.length) return false;
    if (_segmentCategory(text[offset]) == _SegmentCategory.whitespace) {
      return false;
    }
    return offset == 0 ||
        _segmentCategory(text[offset - 1]) != _segmentCategory(text[offset]);
  }

  static _SegmentCategory _segmentCategory(String character) {
    if (character.trim().isEmpty) return _SegmentCategory.whitespace;
    return _isWordCharacter(character)
        ? _SegmentCategory.word
        : _SegmentCategory.punctuation;
  }

  /// The strong direction of [character], or null when it is neutral.
  ///
  /// Deliberately covers the strong ranges that matter here rather than
  /// implementing the Unicode bidi character database: Hebrew, Arabic and their
  /// presentation forms are RTL; Latin, Greek and Cyrillic are LTR; everything
  /// else — digits, spaces, punctuation — is neutral and defers to the
  /// paragraph, which is what the bidi algorithm does with them anyway.
  static TextDirection? directionOf(String character) {
    if (character.isEmpty) return null;
    final code = character.runes.first;

    // Hebrew, Arabic, Syriac, Thaana, N'Ko, Samaritan, Mandaic.
    if (code >= 0x0590 && code <= 0x08FF) return TextDirection.rtl;
    // Hebrew and Arabic presentation forms.
    if (code >= 0xFB1D && code <= 0xFDFF) return TextDirection.rtl;
    if (code >= 0xFE70 && code <= 0xFEFF) return TextDirection.rtl;

    // Basic Latin letters.
    if ((code >= 0x0041 && code <= 0x005A) ||
        (code >= 0x0061 && code <= 0x007A)) {
      return TextDirection.ltr;
    }
    // Latin-1 supplement through Greek and Cyrillic.
    if (code >= 0x00C0 && code <= 0x058F) return TextDirection.ltr;

    return null;
  }
}

enum _SegmentCategory { whitespace, word, punctuation }

/// One visual line's glyph boxes, each kept with the character offset it draws.
///
/// A "visual line" is a row of the laid-out paragraph — what a soft wrap
/// creates. It is not a block and not a sentence, and in bidirectional text its
/// offsets are not in visual order: the mixed line
/// `…בעברית This is what…` holds a descending Hebrew run and an ascending
/// English one side by side.
class VisualLine {
  VisualLine({
    required this.top,
    required this.boxes,
    required this.offsets,
  });

  /// The top of this line's glyph boxes. **Not** the y a caret is drawn at:
  /// the editor's line-height multiplier puts the caret above the glyph box
  /// (measured at -0.40), and comparing the two conventions directly is what
  /// made every caret past the first line resolve to the line above it.
  final double top;

  final List<TextBox> boxes;
  final List<int> offsets;
}
