import 'package:flutter/material.dart';

import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import 'timbre_bus.dart';

/// An empty list: the bus of the brand, what is missing and, optionally,
/// what to try next.
class TimbreEmptyState extends StatelessWidget {
  const TimbreEmptyState(this.message, {super.key, this.detail});

  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TimbreBus(height: 44, palette: TimbreBusPalette.onLight),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: TimbreFonts.fira,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: TimbreColors.tinta)),
          if (detail != null) ...[
            const SizedBox(height: 4),
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
