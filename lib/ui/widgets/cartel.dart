import 'package:flutter/material.dart';

import '../spoken_text.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import 'timbre_bus.dart';

// The "cartel": an amber dot-matrix LED display on ink, like the
// destination sign of a bus. Rules (board "El cartel en la interfaz"):
//  * only for what the bus says live (GPS arrivals) and the brand plate;
//  * one cartel per screen;
//  * Doto from 19 px up, amber only on tinta or azul, never on white;
//  * a timetable estimate never gets a cartel: it stays a white card.

/// Brand plate for headers: amber bus + "TIMBRE MVD".
class CartelCompacto extends StatelessWidget {
  const CartelCompacto({super.key, this.fontSize = 22});

  /// Size of the dot-matrix letters (min 19).
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final f = fontSize < TimbreFonts.dotoMinSize
        ? TimbreFonts.dotoMinSize
        : fontSize;
    return Semantics(
      label: 'Timbre MVD',
      container: true,
      child: ExcludeSemantics(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: TimbreColors.tinta,
              borderRadius: BorderRadius.circular(f * 0.41),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: f * 0.55,
                vertical: f * 0.32,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TimbreBus(height: f * 1.09, palette: TimbreBusPalette.led),
                  SizedBox(width: f * 0.41),
                  Text.rich(
                    const TextSpan(
                      text: 'TIMBRE',
                      children: [
                        TextSpan(
                          text: ' MVD',
                          style: TextStyle(color: TimbreColors.ambarTenue),
                        ),
                      ],
                    ),
                    style: TimbreText.cartel(f).copyWith(letterSpacing: 1),
                    maxLines: 1,
                    softWrap: false,
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

/// "Live" mark (GPS): a dot with a soft halo. Blue on white, amber
/// inside the cartel.
class LiveDot extends StatelessWidget {
  const LiveDot({super.key, this.color = TimbreColors.azul, this.size = 12});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final halo = color == TimbreColors.ambar ? 0.25 : 0.18;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: halo),
        ),
        child: Center(
          child: SizedBox.square(
            dimension: size * 0.5,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// "LLEGANDO" chip: the only moment a cartel enters a list
/// (etaMinutes <= 0).
class LlegandoChip extends StatelessWidget {
  const LlegandoChip({super.key, this.fontSize = 20});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'llegando',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TimbreColors.tinta,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              'LLEGANDO',
              style: TimbreText.cartel(fontSize).copyWith(letterSpacing: 1),
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
      ),
    );
  }
}

/// Live (GPS) minutes in white lists: blue dot-matrix digits + "min".
/// Timetable times must use [TimbreText.scheduleTime] instead.
class MinutosEnVivo extends StatelessWidget {
  const MinutosEnVivo({super.key, required this.minutes, this.size = 30});

  final int minutes;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (minutes <= 0) return const LlegandoChip();
    return Semantics(
      label: 'en ${_minutosLabel(minutes)}, con GPS',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const LiveDot(),
            const SizedBox(width: 5),
            Text('$minutes', style: TimbreText.liveMinutes(size)),
            const SizedBox(width: 4),
            const Text('min', style: TimbreText.minuteUnit),
          ],
        ),
      ),
    );
  }
}

/// The stop display: the next GPS-tracked bus, as the sign at the stop
/// would show it. For a timetable estimate do not use this widget.
class CartelParada extends StatelessWidget {
  const CartelParada({
    super.key,
    required this.line,
    required this.destination,
    required this.etaMinutes,
    this.updatedAt,
    this.accessible = false,
    this.airConditioning = false,
    this.zeroEmission = false,
    this.onTap,
  });

  final String line;
  final String destination;

  /// Minutes until the bus arrives; 0 or less shows "LLEGANDO".
  final int etaMinutes;
  final DateTime? updatedAt;
  final bool accessible;
  final bool airConditioning;
  final bool zeroEmission;
  final VoidCallback? onTap;

  bool get _arriving => etaMinutes <= 0;

  String get _semanticLabel {
    final parts = <String>[
      'Próximo: $line a ${spokenName(destination)}',
      _arriving ? 'llegando' : 'llega en ${_minutosLabel(etaMinutes)}',
      'con GPS',
      if (accessible) 'accesible',
      if (airConditioning) 'aire acondicionado',
      if (zeroEmission) 'cero emisiones',
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final amenities = <Widget>[
      if (accessible) _amenity(Icons.accessible, 'Accesible'),
      if (airConditioning) _amenity(Icons.ac_unit, 'Aire acondicionado'),
      if (zeroEmission) _amenity(Icons.bolt, 'Cero emisiones'),
    ];

    return Semantics(
      button: onTap != null,
      label: _semanticLabel,
      // ExcludeSemantics drops the InkWell's tap action too
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: TimbreColors.tinta,
          borderRadius: BorderRadius.circular(TimbreRadii.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('PRÓXIMO', style: TimbreText.cartelLabel),
                      const Spacer(),
                      if (updatedAt != null)
                        Text(
                          'Actualizado ${_hhmm(updatedAt!)}',
                          style: TimbreText.cartelLabel.copyWith(
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(line, style: TimbreText.cartel(30)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          destination,
                          style: TimbreText.cartel(24),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _arriving
                            ? FittedBox(
                                alignment: Alignment.centerLeft,
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'LLEGANDO',
                                  style: TimbreText.cartel(44)
                                      .copyWith(letterSpacing: 1),
                                ),
                              )
                            // Scales down instead of overflowing with big
                            // text settings or 3-digit minutes
                            : FittedBox(
                                alignment: Alignment.bottomLeft,
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 22),
                                      child: LiveDot(
                                          color: TimbreColors.ambar, size: 16),
                                    ),
                                    const SizedBox(width: 10),
                                    Text('$etaMinutes',
                                        style: TimbreText.cartel(72)),
                                    const SizedBox(width: 10),
                                    Text('min', style: TimbreText.cartel(26)),
                                  ],
                                ),
                              ),
                      ),
                      if (amenities.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: amenities,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _amenity(IconData icon, String label) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: TimbreColors.sobreAzul),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: TimbreFonts.fira,
                fontSize: 13,
                color: TimbreColors.sobreAzul,
              ),
            ),
          ],
        ),
      );
}

/// One-line cartel for the "Estoy esperando" sheet: line, destination and
/// the live minutes of the bus being followed.
class CartelTira extends StatelessWidget {
  const CartelTira({
    super.key,
    required this.line,
    required this.destination,
    required this.etaMinutes,
  });

  final String line;
  final String destination;
  final int etaMinutes;

  @override
  Widget build(BuildContext context) {
    final arriving = etaMinutes <= 0;
    return Semantics(
      label: '$line a ${spokenName(destination)}, '
          '${arriving ? 'llegando' : 'llega en ${_minutosLabel(etaMinutes)}'}'
          ', con GPS',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TimbreColors.tinta,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(line, style: TimbreText.cartel(26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    destination,
                    style: TimbreText.cartel(22),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                if (arriving)
                  Text('LLEGANDO', style: TimbreText.cartel(22))
                else ...[
                  const LiveDot(color: TimbreColors.ambar),
                  const SizedBox(width: 6),
                  Text('$etaMinutes', style: TimbreText.cartel(34)),
                  const SizedBox(width: 4),
                  Text('min', style: TimbreText.cartel(19)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _minutosLabel(int minutes) =>
    minutes == 1 ? '1 minuto' : '$minutes minutos';

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
