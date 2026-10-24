import 'package:flutter/material.dart';

import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';

/// Big page title under the brand plate in the blue header ("Mis paradas",
/// "Servicios", "Horarios"), with an optional one-line subtitle.
///
/// The height follows the system font size: a fixed height cut the title
/// with the "Largest" text setting.
class PageTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const PageTitleBar({
    super.key,
    required this.title,
    required this.textScaler,
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

  static const defaultSubtitleStyle = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontSize: 14,
    height: 1.2,
    color: TimbreColors.sobreAzul,
  );

  // Breathing room under the plate, then the title, then the bottom edge
  static const _top = 5.0;
  static const _bottom = 14.0;
  static const _gap = 6.0;

  @override
  Size get preferredSize {
    const t = TimbreText.pageTitle;
    var h = _top + textScaler.scale(t.fontSize!) * t.height! + _bottom;
    if (subtitle != null) {
      h += _gap +
          textScaler.scale(subtitleStyle.fontSize!) * subtitleStyle.height!;
    }
    return Size.fromHeight(h.ceilToDouble());
  }

  @override
  Widget build(BuildContext context) {
    Widget bar = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: TimbreText.pageTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: _gap),
          Row(children: [
            Flexible(
              child: Text(
                subtitle!,
                style: subtitleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (subtitleTrailing != null)
              Text(subtitleTrailing!, style: subtitleStyle, maxLines: 1),
          ]),
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
      padding: const EdgeInsets.fromLTRB(16, _top, 16, _bottom),
      child: Align(alignment: Alignment.topLeft, child: bar),
    );
  }
}
