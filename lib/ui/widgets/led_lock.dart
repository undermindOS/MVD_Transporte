import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/timbre_tokens.dart';

/// The lock of the lock screen, drawn on the LED board: big amber dots
/// that boot like a destination sign (a wave lights them up), a shackle
/// that drops into place one row at a time, then a scan line every few
/// seconds. While [scanning] (the system unlock prompt is open) the scan
/// line keeps sweeping. With reduced motion it is a still, closed lock.
class LedLock extends StatefulWidget {
  const LedLock({super.key, this.pitch = 8, this.scanning = false});

  /// Distance between dot centers; the lock is 13 × 18 dots.
  final double pitch;

  final bool scanning;

  static const cols = 13;
  static const rows = _raise + 6 + 9;

  // Pixel art: '#' lit, '.' nothing. The keyhole is drawn as unlit LEDs.
  static const _shackle = [
    '...#######...',
    '..#########..',
    '..##.....##..',
    '..##.....##..',
    '..##.....##..',
    '..##.....##..',
  ];
  static const _body = [
    '.###########.',
    '#############',
    '#############',
    '#####ooo#####',
    '#####ooo#####',
    '######o######',
    '######o######',
    '#############',
    '.###########.',
  ];

  /// Rows the shackle starts above its place (open), before it drops.
  static const _raise = 3;

  @override
  State<LedLock> createState() => _LedLockState();
}

class _LedLockState extends State<LedLock> with TickerProviderStateMixin {
  static const _idlePeriod = Duration(milliseconds: 3600);
  static const _scanPeriod = Duration(milliseconds: 900);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _loop();
    });

  late final AnimationController _scan =
      AnimationController(vsync: this, duration: _idlePeriod);

  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      _intro.value = 1;
      _scan
        ..stop()
        ..value = 0;
    } else if (_intro.isDismissed) {
      _intro.forward();
    }
  }

  @override
  void didUpdateWidget(LedLock old) {
    super.didUpdateWidget(old);
    if (old.scanning != widget.scanning && _intro.isCompleted) _loop();
  }

  void _loop() {
    if (_still) return;
    _scan
      ..duration = widget.scanning ? _scanPeriod : _idlePeriod
      ..repeat();
  }

  @override
  void dispose() {
    _intro.dispose();
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(LedLock.cols * widget.pitch, LedLock.rows * widget.pitch),
          painter: _LedLockPainter(
            intro: _intro,
            scan: _scan,
            scanning: widget.scanning,
          ),
        ),
      ),
    );
  }
}

class _LedLockPainter extends CustomPainter {
  _LedLockPainter({
    required this.intro,
    required this.scan,
    required this.scanning,
  }) : super(repaint: Listenable.merge([intro, scan]));

  final Animation<double> intro;
  final Animation<double> scan;
  final bool scanning;

  static const _lightAmber = Color(0xFFFFE2A3);

  @override
  void paint(Canvas canvas, Size size) {
    final p = size.width / LedLock.cols;
    final t = intro.value;

    // Boot: a diagonal wave lights the body, then the open shackle
    final bootBody = (t / 0.45).clamp(0.0, 1.0);
    final bootShackle = ((t - 0.3) / 0.25).clamp(0.0, 1.0);
    // The shackle drops one row per step, like an LED animation
    final drop = ((t - 0.6) / 0.2).clamp(0.0, 1.0);
    final raise = LedLock._raise - (drop * LedLock._raise).floor();
    // Locked: one flash of the glow
    final flash = t > 0.8 ? math.sin((t - 0.8) / 0.2 * math.pi) : 0.0;

    // Scan line position in rows, if any
    double? scanRow;
    final s = scan.value;
    if (t >= 1) {
      if (scanning) {
        scanRow = s * (LedLock.rows + 4) - 2;
      } else if (s < 0.25) {
        scanRow = s / 0.25 * (LedLock.rows + 4) - 2;
      }
    }

    final lit = <Offset>[];
    final bright = <Offset>[];
    final dim = <Offset>[];

    Offset at(int x, int y) => Offset((x + 0.5) * p, (y + 0.5) * p);
    // Wave order of a cell, 0..1 from top left to bottom right
    double order(int x, int y, int h) =>
        (y + x * 0.5) / (h + LedLock.cols * 0.5);
    bool hot(int y) => scanRow != null && (y - scanRow).abs() < 1.2;

    const bodyTop = LedLock._raise + 6;
    for (var y = 0; y < LedLock._body.length; y++) {
      final row = LedLock._body[y];
      for (var x = 0; x < LedLock.cols; x++) {
        final c = row[x];
        if (c == '.') continue;
        final o = at(x, bodyTop + y);
        if (c == 'o' || order(x, y, LedLock._body.length) > bootBody) {
          dim.add(o);
        } else {
          (hot(bodyTop + y) ? bright : lit).add(o);
        }
      }
    }
    final shackleTop = LedLock._raise - raise;
    for (var y = 0; y < LedLock._shackle.length; y++) {
      final row = LedLock._shackle[y];
      for (var x = 0; x < LedLock.cols; x++) {
        if (row[x] != '#') continue;
        final o = at(x, shackleTop + y);
        if (order(x, y, LedLock._shackle.length) > bootShackle) {
          dim.add(o);
        } else {
          (hot(shackleTop + y) ? bright : lit).add(o);
        }
      }
    }

    final dot = p * 0.74;
    Paint dots(Color color) => Paint()
      ..color = color
      ..strokeWidth = dot
      ..strokeCap = StrokeCap.round;

    canvas.drawPoints(ui.PointMode.points, dim,
        dots(TimbreColors.ambar.withValues(alpha: 0.16)));

    // Glow under the lit dots: one blurred layer for all of them
    final glow = [...lit, ...bright];
    if (glow.isNotEmpty) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: p * 0.7, sigmaY: p * 0.7),
      );
      canvas.drawPoints(
        ui.PointMode.points,
        glow,
        dots(TimbreColors.ambar.withValues(alpha: 0.45 + 0.45 * flash))
          ..strokeWidth = dot * 1.25,
      );
      canvas.restore();
    }
    canvas.drawPoints(ui.PointMode.points, lit, dots(TimbreColors.ambar));
    canvas.drawPoints(ui.PointMode.points, bright, dots(_lightAmber));

    // While the system prompt is open: a reading beam across the lock
    if (scanning && scanRow != null) {
      final y = (scanRow + 0.5) * p;
      final beam = Paint()
        ..color = _lightAmber.withValues(alpha: 0.7)
        ..strokeWidth = p * 0.22
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(-p * 0.5, y),
          Offset(size.width + p * 0.5, y),
          Paint()
            ..color = TimbreColors.ambar.withValues(alpha: 0.5)
            ..strokeWidth = p * 0.9
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, p * 0.6));
      canvas.drawLine(
          Offset(-p * 0.5, y), Offset(size.width + p * 0.5, y), beam);
    }
  }

  @override
  bool shouldRepaint(_LedLockPainter old) =>
      old.intro != intro || old.scan != scan || old.scanning != scanning;
}
