import 'package:flutter/material.dart';

import '../../models/arrivals_board.dart';
import '../../models/bus_arrival.dart';
import '../../models/bus_stop.dart';
import '../spoken_text.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import '../widgets/arrival_row.dart';
import '../widgets/cartel.dart';
import '../widgets/line_badge.dart';
import '../widgets/pixel_icon.dart';
import 'map_buses.dart';

/// "Parada 574, San Jose y Andes": what screen readers hear for a stop.
String stopPhrase(BusStop stop) => stop.name == 'Parada ${stop.id}'
    ? stop.name
    : 'Parada ${stop.id}, ${spokenName(stop.name)}';

/// A tapped bus: its line and destination, and when it reaches each saved
/// stop it approaches. The badge is lit while [MapBus.live], each row while
/// its [MapBusEta.live].
class BusSheet extends StatelessWidget {
  const BusSheet({super.key, required this.bus, required this.stops});

  final MapBus bus;

  /// The saved stops by id, for their names.
  final Map<int, BusStop> stops;

  @override
  Widget build(BuildContext context) {
    final to = bus.destination.isEmpty
        ? ''
        : ' a ${spokenName(bus.destination)}';
    return _Sheet(
      children: [
        Semantics(
          container: true,
          header: true,
          label: 'Línea ${bus.line}$to',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                LineBadge(bus.line, live: bus.live),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    bus.destination.isEmpty
                        ? 'Línea ${bus.line}'
                        : bus.destination,
                    style: TimbreText.destination,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
        for (final eta in bus.etas) _EtaRow(eta: eta, stop: stops[eta.stopId]),
      ],
    );
  }
}

/// "a la parada 574 · SAN JOSE y ANDES" and the minutes there.
class _EtaRow extends StatelessWidget {
  const _EtaRow({required this.eta, required this.stop});

  final MapBusEta eta;
  final BusStop? stop;

  bool get _named => stop != null && stop!.name != 'Parada ${eta.stopId}';

  String get _sentence {
    final where = _named
        ? 'A la parada ${eta.stopId}, ${spokenName(stop!.name)}'
        : 'A la parada ${eta.stopId}';
    final when = !eta.live
        ? 'alrededor de las ${eta.clockTime}, estimado'
        : eta.etaMinutes <= 0
        ? 'llegando, con GPS'
        : 'llega en ${eta.etaMinutes == 1 ? '1 minuto' : '${eta.etaMinutes} minutos'}, con GPS';
    return '$where, $when';
  }

  @override
  Widget build(BuildContext context) {
    final where = _named
        ? 'a la parada ${eta.stopId} · ${stop!.name}'
        : 'a la parada ${eta.stopId}';
    // Lit digits only for a current GPS time; an estimate shows its clock
    final time = eta.live
        ? MinutosEnVivo(minutes: eta.etaMinutes, size: 26)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PixelIcon(
                PixelGlyphs.clock,
                size: TimbreIconSize.mark,
                color: TimbreColors.tenue,
              ),
              const SizedBox(width: 5),
              Text(
                '~${eta.clockTime}',
                style: TimbreText.scheduleTime.copyWith(fontSize: 20),
              ),
            ],
          );
    final text = Text(where, style: TimbreText.body);
    final stacked = TimbreText.isLarge(context);
    return Semantics(
      container: true,
      label: _sentence,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    text,
                    const SizedBox(height: 6),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FittedBox(fit: BoxFit.scaleDown, child: time),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 8),
                    time,
                  ],
                ),
        ),
      ),
    );
  }
}

/// A tapped stop: its name and the next buses on its board, as in Mis
/// paradas. After a failed refresh the last ones stay, as estimates.
class StopSheet extends StatelessWidget {
  const StopSheet({
    super.key,
    required this.stop,
    required this.board,
    required this.failed,
    required this.now,
  });

  final BusStop stop;

  /// The newest board of the stop, if any.
  final ArrivalsBoard? board;

  /// The latest refresh of the stop failed.
  final bool failed;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      children: [
        Semantics(
          container: true,
          header: true,
          label: stopPhrase(stop),
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stop.name, style: TimbreText.stopName),
                const SizedBox(height: 3),
                Text(
                  '#${stop.id}',
                  style: TimbreText.caption.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
        ..._rows(),
      ],
    );
  }

  List<Widget> _rows() {
    final board = this.board;
    final age = board == null ? null : now.difference(board.fetchedAt);
    const waiting = Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
    // Offline must not look like "no buses are coming"
    const offline = _SheetNote(
      icon: PixelGlyphs.warning,
      color: TimbreColors.rojoLed,
      text: 'No se pudo actualizar. Revisá la conexión.',
    );
    if (board == null || age! >= MapBuses.staleFor) {
      return [failed ? offline : waiting];
    }
    final live = !failed && age < MapBuses.liveFor;
    final cutoff = now.subtract(MapBuses.staleRowGrace);
    final List<BusArrival> arrivals = live
        ? board.arrivals
        : board.arrivals.where((a) => !a.expectedAt.isBefore(cutoff)).toList();
    if (arrivals.isEmpty) {
      if (!live) return [failed ? offline : waiting];
      return const [
        _SheetNote(
          icon: PixelGlyphs.bus,
          color: TimbreColors.tenue,
          text: 'Sin ómnibus próximos',
        ),
      ];
    }
    final shown = arrivals.take(6).toList();
    return [
      for (var i = 0; i < shown.length; i++) ...[
        if (i > 0) const Divider(indent: 14, endIndent: 14),
        ArrivalRow(arrival: shown[i], stale: !live),
      ],
    ];
  }
}

/// A bottom sheet that scrolls when its rows are taller than the screen.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: TimbreSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// One line in a sheet when there are no rows to show.
class _SheetNote extends StatelessWidget {
  const _SheetNote({
    required this.icon,
    required this.color,
    required this.text,
  });

  final PixelGlyph icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          PixelIcon(icon, size: TimbreIconSize.row, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TimbreText.subtitle.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
