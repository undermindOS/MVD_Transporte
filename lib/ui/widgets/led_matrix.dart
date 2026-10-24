import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/timbre_tokens.dart';

/// The unlit LEDs of a bus destination board: a dot grid that turns the
/// brand-blue surfaces (header, Servicios tiles) into the board the
/// cartel lives on. Texture only: live data keeps the lit dot-matrix
/// digits, timetables never get dots.
class LedMatrix extends StatelessWidget {
  const LedMatrix({
    super.key,
    this.pitch = 6,
    this.dot = 2,
    this.color = TimbreColors.azulNoche,
    this.opacity = 0.55,
    this.fadeFrom,
  });

  /// Distance between dot centers.
  final double pitch;

  /// Dot diameter.
  final double dot;

  final Color color;
  final double opacity;

  /// When set, the dots fade out from this side (full) to the opposite one
  /// (none), so text on the board stays clean.
  final AlignmentGeometry? fadeFrom;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _LedMatrixPainter(
              pitch: pitch,
              dot: dot,
              color: color.withValues(alpha: opacity),
              fadeFrom: fadeFrom?.resolve(Directionality.maybeOf(context)),
            ),
          ),
        ),
      ),
    );
  }
}

class _LedMatrixPainter extends CustomPainter {
  _LedMatrixPainter({
    required this.pitch,
    required this.dot,
    required this.color,
    required this.fadeFrom,
  });

  final double pitch;
  final double dot;
  final Color color;
  final Alignment? fadeFrom;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final points = <Offset>[];
    // Centered grid: the same margin on both sides of the board
    final cols = (size.width / pitch).floor();
    final rows = (size.height / pitch).floor();
    final x0 = (size.width - (cols - 1) * pitch) / 2;
    final y0 = (size.height - (rows - 1) * pitch) / 2;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        points.add(Offset(x0 + c * pitch, y0 + r * pitch));
      }
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = dot
      ..strokeCap = StrokeCap.round;
    final from = fadeFrom;
    if (from != null) {
      final rect = Offset.zero & size;
      paint.shader = ui.Gradient.linear(
        from.withinRect(rect),
        (-from).withinRect(rect),
        [color, color.withValues(alpha: 0)],
      );
    }
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(_LedMatrixPainter old) =>
      old.pitch != pitch ||
      old.dot != dot ||
      old.color != color ||
      old.fadeFrom != fadeFrom;
}
