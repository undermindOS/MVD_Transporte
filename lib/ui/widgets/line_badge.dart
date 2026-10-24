import 'package:flutter/material.dart';

import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';

/// Line number badge. Filled = the bus has GPS; outlined = timetable only.
/// The difference does not rely on color alone.
class LineBadge extends StatelessWidget {
  const LineBadge(
    this.line, {
    super.key,
    this.live = true,
    this.compact = false,
  });

  final String line;
  final bool live;

  /// Smaller badge for dense lists (timetables).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fontSize = compact ? 17.0 : 19.0;
    final width = compact ? 52.0 : 46.0;
    final radius = compact ? 7.0 : TimbreRadii.badge;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: width, maxWidth: width + 24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: live ? TimbreColors.azul : TimbreColors.blanco,
          borderRadius: BorderRadius.circular(radius),
          border: live ? null : Border.all(color: TimbreColors.azul, width: 2),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: live ? 7 : 5, vertical: 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              line,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TimbreText.lineBadge.copyWith(
                fontSize: fontSize,
                color: live ? TimbreColors.blanco : TimbreColors.azul,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
