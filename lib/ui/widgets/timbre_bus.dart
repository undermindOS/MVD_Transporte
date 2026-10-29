import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/timbre_tokens.dart';
import 'led_matrix.dart';

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

  /// The amber bus of the plate, the icon and the empty boards: one light
  /// color, like a real sign.
  static const led = TimbreBusPalette(
    body: TimbreColors.ambar,
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
    this.palette = TimbreBusPalette.led,
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

/// The app icon as on the home screen: the bus lit in amber on the ink
/// board. The same layers as the launcher icon (assets/README.md): ink,
/// unlit LEDs, the bloom of the lit bus, then the bus with its sign and
/// windshield cut out, so the board shows through.
class TimbreAppIcon extends StatelessWidget {
  const TimbreAppIcon({
    super.key,
    required this.size,
    this.semanticLabel,
  });

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final icon = _board();
    if (semanticLabel == null) return ExcludeSemantics(child: icon);
    return Semantics(label: semanticLabel, image: true, child: icon);
  }

  Widget _board() {
    final bus = CustomPaint(
      size: Size.square(size),
      painter: TimbreBusPainter(
        palette: TimbreBusPalette.led,
        detail: TimbreBusDetail.forIconSize(size),
        tile: true,
        tileColor: Colors.transparent,
        cutout: true,
      ),
    );
    final bloom = size * 0.022;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 232 / 1024),
      child: SizedBox.square(
        dimension: size,
        child: Stack(children: [
          const Positioned.fill(child: ColoredBox(color: TimbreColors.tinta)),
          Positioned.fill(
            child: LedMatrix(pitch: size / 32, dot: size * 10 / 1024),
          ),
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: bloom, sigmaY: bloom),
            child: Opacity(opacity: 0.45, child: bus),
          ),
          bus,
        ]),
      ),
    );
  }
}

/// Paints the bus in its 1024-unit design space. With [tile] the canvas is
/// the full 1024 × 1024 icon (a [tileColor] rounded square); without it,
/// the canvas is the 724 × 700 lockup box starting at (150, 160).
class TimbreBusPainter extends CustomPainter {
  const TimbreBusPainter({
    required this.palette,
    required this.detail,
    this.tile = false,
    this.tileColor = TimbreColors.tinta,
    this.cutout = false,
  });

  final TimbreBusPalette palette;
  final TimbreBusDetail detail;
  final bool tile;
  final Color tileColor;

  /// The sign, windshield and corner lights are holes instead of
  /// [TimbreBusPalette.ink]: whatever is behind the bus shows through.
  final bool cutout;

  @override
  void paint(Canvas canvas, Size size) {
    if (cutout) canvas.saveLayer(Offset.zero & size, Paint());
    canvas.save();
    if (tile) {
      final s = size.width / 1024;
      canvas.scale(s);
      canvas.drawRRect(
        RRect.fromLTRBR(0, 0, 1024, 1024, const Radius.circular(232)),
        Paint()..color = tileColor,
      );
      canvas.translate(0, -6);
    } else {
      final s = size.height / 700;
      canvas.scale(s);
      canvas.translate(-150, -160);
    }

    final body = Paint()..color = palette.body;
    final ink = Paint()
      ..color = palette.ink
      ..blendMode = cutout ? BlendMode.clear : BlendMode.srcOver;
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
          ..blendMode = ink.blendMode
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
    if (cutout) canvas.restore();
  }

  @override
  bool shouldRepaint(TimbreBusPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.detail != detail ||
      oldDelegate.tile != tile ||
      oldDelegate.tileColor != tileColor ||
      oldDelegate.cutout != cutout;
}
