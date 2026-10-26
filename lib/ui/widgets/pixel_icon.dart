import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

part 'pixel_glyphs.dart';

/// A 12 × 12 pixel glyph: 12 strings of 12 cells, '#' lit.
class PixelGlyph {
  const PixelGlyph(this.rows);

  final List<String> rows;

  static const size = 12;
}

/// An icon drawn like the dot-matrix letters: square pixels with a small
/// gap, so icons and Doto read as one board. Takes its color and size from
/// the surrounding [IconTheme] (app bar, navigation, buttons) unless given.
///
/// [glow] adds the soft light of a lit LED, for icons that are "on".
class PixelIcon extends StatelessWidget {
  const PixelIcon(
    this.glyph, {
    super.key,
    this.size,
    this.color,
    this.glow = false,
    this.semanticLabel,
  });

  final PixelGlyph glyph;
  final double? size;
  final Color? color;
  final bool glow;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final ink = color ?? theme.color ?? const Color(0xFFFFB21E);
    final icon = SizedBox.square(
      dimension: side,
      child: CustomPaint(painter: _PixelPainter(glyph, ink, glow)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: icon);
    return Semantics(label: semanticLabel, image: true, child: icon);
  }
}

class _PixelPainter extends CustomPainter {
  _PixelPainter(this.glyph, this.color, this.glow);

  final PixelGlyph glyph;
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final p = size.width / PixelGlyph.size;
    // The gap between pixels, like the dots of the Doto letters
    final gap = p * 0.14;
    final path = Path();
    for (var y = 0; y < PixelGlyph.size; y++) {
      final row = glyph.rows[y];
      for (var x = 0; x < PixelGlyph.size; x++) {
        if (row.codeUnitAt(x) != 0x23) continue; // '#'
        path.addRect(Rect.fromLTWH(
            x * p + gap / 2, y * p + gap / 2, p - gap, p - gap));
      }
    }
    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, p * 1.1),
      );
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PixelPainter old) =>
      old.glyph != glyph || old.color != color || old.glow != glow;
}
