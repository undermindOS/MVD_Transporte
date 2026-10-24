import 'package:flutter/material.dart';

import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import 'led_matrix.dart';
import 'timbre_bus.dart';

/// An empty list as a destination sign with nothing to announce: the bus
/// and a short [sign] in amber dots ("SIN NOVEDADES"), then what to try.
class TimbreEmptyState extends StatelessWidget {
  const TimbreEmptyState(
    this.message, {
    super.key,
    required this.sign,
    this.detail,
  });

  /// What screen readers hear instead of the uppercase [sign].
  final String message;

  /// Short and uppercase: it is shown in the dot-matrix letters.
  final String sign;

  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            container: true,
            label: message,
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: TimbreColors.tinta,
                borderRadius: BorderRadius.circular(TimbreRadii.card),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TimbreRadii.card),
                child: Stack(children: [
                  const Positioned.fill(
                    child: LedMatrix(color: TimbreColors.ambar, opacity: 0.11),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 20, 14),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const TimbreBus(
                          height: 26, palette: TimbreBusPalette.led),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          sign,
                          style: TimbreText.cartel(20)
                              .copyWith(letterSpacing: 1, height: 1.15),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 14),
            Text(detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: TimbreFonts.fira,
                    fontSize: 14,
                    height: 1.4,
                    color: TimbreColors.grisTexto)),
          ],
        ],
      ),
    );
  }
}
