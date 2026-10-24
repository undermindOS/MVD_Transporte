import 'package:flutter/material.dart';

import '../theme/timbre_tokens.dart';

/// Colors of the bus glyph: [body] for the bodywork, mirrors and wheels,
/// [ink] for the destination sign, windshield and corner lights, [light]
/// for the bell and the LED bar inside the sign.
@immutable
class TimbreBusPalette {
  final Color body;
  final Color ink;
  final Color light;

  const TimbreBusPalette({
    required this.body,
    required this.ink,
    required this.light,
  });

  /// White bus on the blue header or app icon.
  static const onBlue = TimbreBusPalette(
    body: TimbreColors.blanco,
    ink: TimbreColors.tinta,
    light: TimbreColors.ambar,
  );

  /// Amber bus inside the LED plate: one light color, like a real sign.
  static const led = TimbreBusPalette(
    body: TimbreColors.ambar,
    ink: TimbreColors.tinta,
    light: TimbreColors.ambar,
  );

  /// Blue bus on white or light backgrounds.
  static const onLight = TimbreBusPalette(
    body: TimbreColors.azul,
    ink: TimbreColors.tinta,
    light: TimbreColors.ambar,
  );

  @override
  bool operator ==(Object other) =>
      other is TimbreBusPalette &&
      other.body == body &&
      other.ink == ink &&
      other.light == light;

  @override
  int get hashCode => Object.hash(body, ink, light);
}

/// Level of detail: the smaller the glyph, the fewer parts survive.
enum TimbreBusDetail {
  /// 56 px and up: bell with clapper, corner lights.
  full,

  /// 40-55 px: bell without clapper, corner lights.
  medium,

  /// 30-39 px: bell without clapper, no lights.
  small,

  /// Under 30 px: the sign is a single amber bar.
  tiny;

  static TimbreBusDetail forHeight(double height) {
    if (height >= 56) return TimbreBusDetail.full;
    if (height >= 40) return TimbreBusDetail.medium;
    if (height >= 30) return TimbreBusDetail.small;
    return TimbreBusDetail.tiny;
  }

  /// Same ladder for the app icon, measured on the whole tile:
  /// 87 · 60 · 40 · 29 px on the brand board.
  static TimbreBusDetail forIconSize(double size) {
    if (size >= 80) return TimbreBusDetail.full;
    if (size >= 50) return TimbreBusDetail.medium;
    if (size >= 35) return TimbreBusDetail.small;
    return TimbreBusDetail.tiny;
  }
}

/// The Timbre MVD bus, front view, drawn from the brand vector (v2 "Aviso").
/// Decorative unless [semanticLabel] is given.
class TimbreBus extends StatelessWidget {
  const TimbreBus({
    super.key,
    required this.height,
    this.palette = TimbreBusPalette.onBlue,
    this.semanticLabel,
  });

  final double height;
  final TimbreBusPalette palette;
  final String? semanticLabel;

  /// Width/height of the glyph's view box (724 × 700).
  static const aspectRatio = 724 / 700;

  @override
  Widget build(BuildContext context) {
    final glyph = CustomPaint(
      size: Size(height * aspectRatio, height),
      painter: TimbreBusPainter(
        palette: palette,
        detail: TimbreBusDetail.forHeight(height),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: glyph);
    return Semantics(label: semanticLabel, image: true, child: glyph);
  }
}

/// App icon: the white bus on a blue rounded square, as on the home screen.
class TimbreAppIcon extends StatelessWidget {
  const TimbreAppIcon({super.key, required this.size, this.semanticLabel});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final icon = CustomPaint(
      size: Size.square(size),
      painter: TimbreBusPainter(
        palette: TimbreBusPalette.onBlue,
        detail: TimbreBusDetail.forIconSize(size),
        tile: true,
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: icon);
    return Semantics(label: semanticLabel, image: true, child: icon);
  }
}

/// Paints the bus in its 1024-unit design space. With [tile] the canvas is
/// the full 1024 × 1024 icon (blue rounded square, glass glare); without it,
/// the canvas is the 724 × 700 lockup box starting at (150, 160).
class TimbreBusPainter extends CustomPainter {
  const TimbreBusPainter({
    required this.palette,
    required this.detail,
    this.tile = false,
  });

  final TimbreBusPalette palette;
  final TimbreBusDetail detail;
  final bool tile;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (tile) {
      final s = size.width / 1024;
      canvas.scale(s);
      canvas.drawRRect(
        RRect.fromLTRBR(0, 0, 1024, 1024, const Radius.circular(232)),
        Paint()..color = TimbreColors.azul,
      );
      canvas.translate(0, -6);
    } else {
      final s = size.height / 700;
      canvas.scale(s);
      canvas.translate(-150, -160);
    }

    final body = Paint()..color = palette.body;
    final ink = Paint()..color = palette.ink;
    final light = Paint()..color = palette.light;

    // Mirror arms and heads
    canvas.drawPath(
      Path()
        ..moveTo(300, 214)
        ..cubicTo(236, 198, 198, 236, 194, 300)
        ..moveTo(724, 214)
        ..cubicTo(788, 198, 826, 236, 830, 300),
      Paint()
        ..color = palette.body
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
        RRect.fromLTRBR(170, 292, 218, 420, const Radius.circular(22)), body);
    canvas.drawRRect(
        RRect.fromLTRBR(806, 292, 854, 420, const Radius.circular(22)), body);

    // Wheels
    canvas.drawRRect(
        RRect.fromLTRBR(296, 742, 388, 846, const Radius.circular(28)), body);
    canvas.drawRRect(
        RRect.fromLTRBR(636, 742, 728, 846, const Radius.circular(28)), body);

    // Bodywork: big radius on top, small at the bottom
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        262,
        178,
        762,
        792,
        topLeft: const Radius.circular(92),
        topRight: const Radius.circular(92),
        bottomLeft: const Radius.circular(40),
        bottomRight: const Radius.circular(40),
      ),
      body,
    );

    // Destination sign with the bell (the "timbre") and the LED bar
    canvas.drawRRect(
        RRect.fromLTRBR(298, 214, 726, 314, const Radius.circular(24)), ink);
    if (detail == TimbreBusDetail.tiny) {
      canvas.drawRRect(
          RRect.fromLTRBR(350, 250, 604, 278, const Radius.circular(14)),
          light);
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(328, 273)
          ..lineTo(328, 254)
          ..arcToPoint(const Offset(376, 254),
              radius: const Radius.circular(24))
          ..lineTo(376, 273)
          ..lineTo(383, 282)
          ..lineTo(321, 282)
          ..close(),
        light,
      );
      if (detail == TimbreBusDetail.full) {
        canvas.drawPath(
          Path()
            ..moveTo(342, 290)
            ..arcToPoint(const Offset(362, 290),
                radius: const Radius.circular(10), clockwise: false),
          Paint()
            ..color = palette.light
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawRRect(
          RRect.fromLTRBR(402, 250, 602, 278, const Radius.circular(14)),
          light);
    }

    // Windshield
    canvas.drawRRect(
        RRect.fromLTRBR(290, 336, 734, 666, const Radius.circular(30)), ink);
    if (tile && detail == TimbreBusDetail.full) {
      final glare = Paint()
        ..color = const Color(0x29FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(334, 620), const Offset(446, 420),
          glare..strokeWidth = 26);
      canvas.drawLine(const Offset(390, 636), const Offset(480, 476),
          glare..strokeWidth = 12);
    }

    // Corner lights, angled
    if (detail == TimbreBusDetail.full || detail == TimbreBusDetail.medium) {
      final lights = Path()
        ..moveTo(282, 702)
        ..lineTo(372, 702)
        ..lineTo(356, 738)
        ..lineTo(282, 738)
        ..close()
        ..moveTo(742, 702)
        ..lineTo(652, 702)
        ..lineTo(668, 738)
        ..lineTo(742, 738)
        ..close();
      canvas.drawPath(lights, ink);
      canvas.drawPath(
        lights,
        Paint()
          ..color = palette.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TimbreBusPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.detail != detail ||
      oldDelegate.tile != tile;
}
