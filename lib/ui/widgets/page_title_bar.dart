import 'package:flutter/material.dart';

import '../theme/timbre_text.dart';

/// Big page title under the brand plate on the header board ("MIS
/// PARADAS", "SERVICIOS", "HORARIOS"), with an optional subtitle that wraps
/// to a second line when it does not fit.
///
/// The height follows the system font size and the subtitle lines: a fixed
/// height cut the title with the "Largest" text setting.
class PageTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const PageTitleBar({
    super.key,
    required this.title,
    required this.textScaler,
    this.width,
    this.subtitle,
    this.subtitleTrailing,
    this.subtitleStyle = defaultSubtitleStyle,
    this.semanticLabel,
  }) : assert(subtitleTrailing == null || subtitle != null);

  final String title;
  final String? subtitle;

  /// End of the subtitle that is never cut: the stop number after a long
  /// stop name.
  final String? subtitleTrailing;

  /// Needs an explicit `height`: [preferredSize] is computed from it.
  final TextStyle subtitleStyle;

  /// Replaces what screen readers hear for the whole bar.
  final String? semanticLabel;

  /// `MediaQuery.textScalerOf(context)` of the page: the app bar asks for
  /// [preferredSize] before this widget builds.
  final TextScaler textScaler;

  /// `MediaQuery.sizeOf(context).width` of the page, for the same reason:
  /// it tells whether the subtitle needs a second line. Without it the
  /// subtitle keeps to one line.
  final double? width;

  static const defaultSubtitleStyle = TimbreText.subtitle;

  /// A long stop name ends in "…" only after this many lines.
  static const subtitleMaxLines = 2;

  // Breathing room under the plate, then the title, then the bottom edge
  static const _top = 5.0;
  static const _bottom = 14.0;
  static const _gap = 6.0;
  static const _side = 16.0;

  @override
  Size get preferredSize {
    const t = TimbreText.pageTitle;
    var h = _top + textScaler.scale(t.fontSize!) * t.height! + _bottom;
    if (subtitle != null) {
      h += _gap +
          _subtitleLines *
              textScaler.scale(subtitleStyle.fontSize!) *
              subtitleStyle.height!;
    }
    return Size.fromHeight(h.ceilToDouble());
  }

  /// Lines of the subtitle at [width], laid out like [build] does: the
  /// trailing part first, the rest of the row for the subtitle.
  int get _subtitleLines {
    final w = width;
    if (w == null || subtitle == null) return 1;
    TextPainter painter(String text, {int? maxLines}) => TextPainter(
          text: TextSpan(text: text, style: subtitleStyle),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
          maxLines: maxLines,
        );
    var room = w - 2 * _side;
    if (subtitleTrailing != null) {
      final trailing = painter(subtitleTrailing!, maxLines: 1)..layout();
      room -= trailing.width;
      trailing.dispose();
    }
    final lines = painter(subtitle!, maxLines: subtitleMaxLines)
      ..layout(maxWidth: room < 0 ? 0 : room);
    final count = lines.computeLineMetrics().length;
    lines.dispose();
    return count.clamp(1, subtitleMaxLines);
  }

  @override
  Widget build(BuildContext context) {
    Widget bar = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // A sign: uppercase on screen, plain words for screen readers
        Semantics(
          header: true,
          label: title,
          excludeSemantics: true,
          // A sign keeps every letter: with the largest fonts it shrinks
          // to the width instead of ending in "…"
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title.toUpperCase(),
              style: TimbreText.pageTitle,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: _gap),
          // Only the subtitle style, as [preferredSize] measured it
          DefaultTextStyle(
            style: subtitleStyle,
            child: Row(
              // The trailing part follows the last line
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    subtitle!,
                    style: subtitleStyle,
                    // As many lines as the bar has room for: a narrower
                    // screen than measured cuts instead of overflowing
                    maxLines: _subtitleLines,
                    overflow: TextOverflow.ellipsis,
                    textWidthBasis: TextWidthBasis.longestLine,
                  ),
                ),
                if (subtitleTrailing != null)
                  Text(subtitleTrailing!, style: subtitleStyle, maxLines: 1),
              ],
            ),
          ),
        ],
      ],
    );
    if (semanticLabel != null) {
      bar = Semantics(
        header: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: bar,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(_side, _top, _side, _bottom),
      child: Align(alignment: Alignment.topLeft, child: bar),
    );
  }
}
