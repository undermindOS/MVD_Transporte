import 'package:flutter/material.dart';

import '../../models/bus_arrival.dart';
import '../spoken_text.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import 'cartel.dart';
import 'line_badge.dart';
import 'pixel_icon.dart';

/// One bus on the board: line badge, destination, comfort marks and, on
/// the right, the minutes in lit digits (GPS) or the timetable time with a
/// clock (no GPS). A followed bus ("Estoy esperando") is lifted and rings.
/// A [stale] bus, kept from the last board after a failed refresh, is an
/// estimate ("~20:01"): never lit, whatever it was.
///
/// With large system fonts the time moves to its own line under the
/// destination, so the destination keeps its room and nothing is cut.
class ArrivalRow extends StatelessWidget {
  const ArrivalRow({
    super.key,
    required this.arrival,
    this.waited = false,
    this.stale = false,
    this.onTap,
  });

  final BusArrival arrival;
  final bool waited;

  /// From the last board that arrived, shown after a failed refresh.
  final bool stale;
  final VoidCallback? onTap;

  // A stale row is never lit, so it does not ring either
  bool get _waited => waited && !stale;

  String get _sentence {
    final a = arrival;
    final to = a.destination.isEmpty ? '' : ' a ${spokenName(a.destination)}';
    final when = stale
        ? 'alrededor de las ${a.clockTime}, estimado'
        : !a.isRealTime
            ? 'horario ${a.etaLabel}, sin GPS'
            : a.etaMinutes <= 0
                ? 'llegando, con GPS'
                : 'llega en ${a.etaMinutes == 1 ? '1 minuto' : '${a.etaMinutes} minutos'}, con GPS';
    return [
      'Línea ${a.line}$to, $when',
      if (a.accessible) 'accesible',
      if (a.airConditioning == true) 'aire acondicionado',
      if (a.zeroEmission == true) 'cero emisiones',
      if (_waited) 'estás esperando este ómnibus',
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final a = arrival;
    final waited = _waited;
    final live = a.isRealTime && !stale;
    final marks = <Widget>[
      if (waited)
        const PixelIcon(PixelGlyphs.bellRing,
            size: 14, color: TimbreColors.ambar, semanticLabel: 'Esperando'),
      if (a.accessible)
        const PixelIcon(PixelGlyphs.accessible,
            size: 14,
            color: TimbreColors.etiquetaCartel,
            semanticLabel: 'Accesible'),
      if (a.airConditioning == true)
        const PixelIcon(PixelGlyphs.snow,
            size: 14,
            color: TimbreColors.etiquetaCartel,
            semanticLabel: 'Aire acondicionado'),
      if (a.zeroEmission == true)
        const PixelIcon(PixelGlyphs.bolt,
            size: 14,
            color: TimbreColors.etiquetaCartel,
            semanticLabel: 'Cero emisiones'),
    ];

    final time = live
        ? MinutosEnVivo(minutes: a.etaMinutes, size: 26)
        : Row(mainAxisSize: MainAxisSize.min, children: [
            const PixelIcon(PixelGlyphs.clock,
                size: 14, color: TimbreColors.tenue),
            const SizedBox(width: 5),
            Text(stale ? '~${a.clockTime}' : a.etaLabel,
                style: TimbreText.scheduleTime.copyWith(fontSize: 20)),
          ]);
    final stacked = TimbreText.isLarge(context);
    final heading = Row(children: [
      LineBadge(a.line, live: live),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              a.destination.isEmpty ? 'Línea ${a.line}' : a.destination,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TimbreText.destination.copyWith(fontSize: 17),
            ),
            if (marks.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: marks),
            ],
          ],
        ),
      ),
      if (!stacked) ...[const SizedBox(width: 8), time],
    ]);

    return Semantics(
      container: true,
      button: onTap != null,
      label: _sentence,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        // The followed bus is lifted from the panel
        color: waited ? TimbreColors.tintaAlta : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: !stacked
                  ? heading
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        heading,
                        const SizedBox(height: 6),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          // Wider than the row only with the very largest
                          // fonts: then it scales down, never cut
                          child: FittedBox(fit: BoxFit.scaleDown, child: time),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
