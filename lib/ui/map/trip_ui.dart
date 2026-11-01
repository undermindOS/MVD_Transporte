import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:latlong2/latlong.dart' show LatLng;

import '../../models/arrivals_board.dart';
import '../../models/bus_arrival.dart';
import '../../models/place.dart';
import '../../services/api/api_result.dart';
import '../../services/mvd_api_service.dart';
import '../../services/nearby_stops_service.dart';
import '../../services/places_service.dart';
import '../../services/rutas/itinerary.dart';
import '../../services/trip_service.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import '../widgets/line_badge.dart';
import '../widgets/pixel_icon.dart';
import '../widgets/segmented.dart';

/// Where a trip ends or starts: a place, a point on the map, or the phone.
typedef TripEnd = ({String name, GeoPoint? point});

/// The trip the person chose: shown on the map until closed.
typedef ChosenTrip = ({Itinerary trip, String from, String to});

/// "14:05", as the app writes times.
String tripClock(DateTime t) =>
    '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

String _minutes(Duration d) {
  final m = d.inMinutes;
  return m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';
}

/// The phone's position for a trip from "Tu ubicación". Tests answer here.
@visibleForTesting
Future<GeoPoint> Function() locateForTrip = () async {
  final Position p = await NearbyStopsService.currentPosition();
  return (lat: p.latitude, lon: p.longitude);
};

/// The planner: from the phone or a place, to [to], leaving now or at a
/// chosen time, walking at most 5, 10 or 15 min at each end. Pops a
/// [ChosenTrip] when an option is tapped.
class TripPlannerSheet extends StatefulWidget {
  const TripPlannerSheet({
    super.key,
    required this.to,
    required this.places,
    required this.now,
  });

  final TripEnd to;

  /// The places to start from, besides the phone.
  final List<Place> places;
  final DateTime Function() now;

  @override
  State<TripPlannerSheet> createState() => _TripPlannerSheetState();
}

class _TripPlannerSheetState extends State<TripPlannerSheet> {
  // null: from the phone
  Place? _from;
  TimeOfDay? _at;
  late int _walk = PlacesService.walkMinutes;

  // The last request: older answers are dropped
  var _asked = 0;
  TripAnswer? _answer;
  String? _error;
  bool _busy = false;

  List<Place> get _starts => [
    for (final p in widget.places)
      if (p.lat != widget.to.point?.lat || p.lon != widget.to.point?.lon) p,
  ];

  @override
  void initState() {
    super.initState();
    _plan();
  }

  DateTime _departAt() {
    final now = widget.now();
    final at = _at;
    if (at == null) return now;
    var t = DateTime(now.year, now.month, now.day, at.hour, at.minute);
    // A time already gone today is tomorrow's
    if (t.isBefore(now.subtract(const Duration(minutes: 1)))) {
      t = t.add(const Duration(days: 1));
    }
    return t;
  }

  Future<void> _plan() async {
    final asked = ++_asked;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final from = _from;
      final GeoPoint start = from == null
          ? await locateForTrip()
          : (lat: from.lat, lon: from.lon);
      final answer = await TripService.plan((
        from: start,
        to: widget.to.point!,
        departAt: _departAt(),
        maxWalkMinutes: _walk,
      ));
      if (!mounted || asked != _asked) return;
      setState(() => _answer = answer);
    } on NearbyStopsException catch (e) {
      if (!mounted || asked != _asked) return;
      setState(() {
        _answer = null;
        _error = switch (e.error) {
          NearbyStopsError.serviceDisabled =>
            'Prendé la ubicación del teléfono, o salí desde uno de tus lugares.',
          NearbyStopsError.permissionDenied ||
          NearbyStopsError.permissionDeniedForever =>
            'Sin permiso de ubicación. Salí desde uno de tus lugares, o '
                'dale permiso a la app en los ajustes.',
          _ =>
            'No se pudo saber dónde estás. Probá de nuevo o salí desde '
                'uno de tus lugares.',
        };
      });
    } catch (e) {
      debugPrint('⚠️ Trip planner: ${e.runtimeType}');
      if (!mounted || asked != _asked) return;
      setState(() {
        _answer = null;
        _error = 'No se pudo buscar el viaje. Probá de nuevo.';
      });
    } finally {
      if (mounted && asked == _asked) setState(() => _busy = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _at ?? TimeOfDay.fromDateTime(widget.now()),
      helpText: 'Hora de salida',
    );
    if (picked == null || !mounted) return;
    setState(() => _at = picked);
    _plan();
  }

  @override
  Widget build(BuildContext context) {
    final answer = _answer;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Cómo llegar a ${widget.to.name}',
              style: TimbreText.stopName,
            ),
          ),
          const SizedBox(height: TimbreSpace.m),
          _FieldRow(
            label: 'Desde',
            child: DropdownButton<Place?>(
              value: _from,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tu ubicación'),
                ),
                for (final p in _starts)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (p) {
                setState(() => _from = p);
                _plan();
              },
            ),
          ),
          _FieldRow(
            label: 'Salir',
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickTime,
                icon: const PixelIcon(PixelGlyphs.clock),
                label: Text(
                  _at == null ? 'Ahora' : 'A las ${_at!.format(context)}',
                ),
              ),
            ),
          ),
          const SizedBox(height: TimbreSpace.s),
          Text('Caminar hasta', style: TimbreText.caption),
          const SizedBox(height: TimbreSpace.xs),
          TimbreSegmented<int>(
            values: PlacesService.walkOptions,
            selected: _walk,
            labelOf: (m) => '$m min',
            semanticLabel: 'Caminar hasta',
            onChanged: (m) {
              setState(() => _walk = m);
              PlacesService.setWalkMinutes(m);
              _plan();
            },
          ),
          const SizedBox(height: TimbreSpace.l),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(TimbreSpace.xl),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error case final error?)
            _Note(
              glyph: PixelGlyphs.warning,
              color: TimbreColors.rojoLed,
              text: error,
            )
          else if (answer != null &&
              answer.options.isEmpty &&
              (answer.noStopNearFrom || answer.noStopNearTo))
            _Note(
              glyph: PixelGlyphs.stop,
              color: TimbreColors.tenue,
              text:
                  'No hay paradas de Montevideo a menos de $_walk min '
                  'caminando de '
                  '${answer.noStopNearFrom ? _from?.name ?? 'tu ubicación' : widget.to.name}.',
            )
          else if (answer != null && answer.options.isEmpty)
            _Note(
              glyph: PixelGlyphs.bus,
              color: TimbreColors.tenue,
              text:
                  'No hay un viaje en ómnibus caminando hasta $_walk min '
                  'en las próximas horas. Probá caminar más o salir a otra hora.',
            )
          else if (answer != null) ...[
            for (final option in answer.options)
              _OptionCard(
                trip: option,
                onTap: () => Navigator.pop<ChosenTrip>(context, (
                  trip: option,
                  from: _from?.name ?? 'Tu ubicación',
                  to: widget.to.name,
                )),
              ),
            const SizedBox(height: TimbreSpace.s),
            Text(
              'Horarios teóricos de la Intendencia de Montevideo '
              '(${_date(answer.sourceDate)}). Al tocar un viaje ves si el '
              'primer ómnibus viene con GPS.',
              style: TimbreText.caption.copyWith(color: TimbreColors.tenue),
            ),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 56, child: Text(label, style: TimbreText.caption)),
        Expanded(child: child),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.glyph, required this.color, required this.text});

  final PixelGlyph glyph;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TimbreSpace.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PixelIcon(glyph, size: TimbreIconSize.row, color: color),
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

/// One option: when it leaves and arrives, how long, and its legs in a row
/// ("🚶6 › 121 › 🚶4"). Timetable times: never amber, never dot-matrix.
class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.trip, required this.onTap});

  final Itinerary trip;
  final VoidCallback onTap;

  String get _spoken {
    final lines = trip.rideLegs.map((r) => r.line).join(' y ');
    final how = trip.walkOnly ? 'a pie' : 'en el $lines';
    return 'Salís ${tripClock(trip.start)}, llegás ${tripClock(trip.end)}, '
        '${_minutes(trip.duration)} $how, caminando ${trip.walkMetres} metros';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TimbreSpace.s),
      child: Semantics(
        button: true,
        label: _spoken,
        excludeSemantics: true,
        child: Material(
          color: TimbreColors.tinta,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TimbreRadii.card),
            side: const BorderSide(color: TimbreColors.lineaNoche),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(TimbreRadii.card),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(TimbreSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TimbreSpace.s,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${tripClock(trip.start)} → ${tripClock(trip.end)}',
                          style: TimbreText.scheduleTime,
                        ),
                      ),
                      Text(
                        _minutes(trip.duration),
                        style: TimbreText.destination,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (i, leg) in trip.legs.indexed) ...[
                        if (i > 0)
                          const PixelIcon(
                            PixelGlyphs.chevronRight,
                            size: TimbreIconSize.mark,
                            color: TimbreColors.tenue,
                          ),
                        switch (leg) {
                          WalkLeg() => _WalkChip(minutes: leg.minutes),
                          RideLeg() => LineBadge(leg.line, live: false),
                        },
                      ],
                    ],
                  ),
                  Text(
                    trip.walkOnly
                        ? 'A pie, ${trip.walkMetres} m'
                        : 'Caminás ${trip.walkMetres} m · '
                              '${trip.rides == 1 ? '1 ómnibus' : '${trip.rides} ómnibus'}',
                    style: TimbreText.caption,
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

class _WalkChip extends StatelessWidget {
  const _WalkChip({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const PixelIcon(
          PixelGlyphs.walk,
          size: TimbreIconSize.row,
          color: TimbreColors.etiquetaCartel,
        ),
        Text('$minutes', style: TimbreText.caption),
      ],
    );
  }
}

/// The chosen trip on the map: walks dotted in paper, rides in amber
/// through their stops, the stops where a bus is taken or left marked.
List<Widget> tripLayers(Itinerary trip) {
  LatLng ll(GeoPoint p) => LatLng(p.lat, p.lon);
  return [
    PolylineLayer(
      polylines: [
        for (final leg in trip.legs)
          switch (leg) {
            WalkLeg() => Polyline(
              points: [ll(leg.from), ll(leg.to)],
              color: TimbreColors.papel,
              strokeWidth: 4,
              pattern: const StrokePattern.dotted(),
            ),
            RideLeg() => Polyline(
              points: [for (final s in leg.stops) LatLng(s.lat, s.lon)],
              color: TimbreColors.ambar,
              strokeWidth: 5,
              borderColor: TimbreColors.noche,
              borderStrokeWidth: 2,
            ),
          },
      ],
    ),
    MarkerLayer(
      markers: [
        for (final ride in trip.rideLegs)
          for (final stop in [ride.boardStop, ride.alightStop])
            Marker(
              point: LatLng(stop.lat, stop.lon),
              width: 14,
              height: 14,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: TimbreColors.tinta,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: TimbreColors.ambar, width: 3),
                  ),
                ),
              ),
            ),
      ],
    ),
  ];
}

/// Every point of [trip], to fit the camera to it.
List<LatLng> tripPoints(Itinerary trip) => [
  for (final leg in trip.legs)
    ...switch (leg) {
      WalkLeg() => [
        LatLng(leg.from.lat, leg.from.lon),
        LatLng(leg.to.lat, leg.to.lon),
      ],
      RideLeg() => [for (final s in leg.stops) LatLng(s.lat, s.lon)],
    },
];

/// The chosen trip, at the bottom of the map: the first bus and when you
/// arrive, its steps, and a way to close it.
class TripBanner extends StatelessWidget {
  const TripBanner({
    super.key,
    required this.chosen,
    required this.onSteps,
    required this.onClose,
  });

  final ChosenTrip chosen;
  final VoidCallback onSteps;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final trip = chosen.trip;
    final first = trip.rideLegs.firstOrNull;
    return Material(
      color: TimbreColors.tinta,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TimbreRadii.card),
        side: const BorderSide(color: TimbreColors.lineaNoche),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            if (first != null) ...[
              LineBadge(first.line, live: false),
              const SizedBox(width: 10),
            ] else ...[
              const PixelIcon(PixelGlyphs.walk, color: TimbreColors.ambar),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'A ${chosen.to}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TimbreText.destination,
                  ),
                  Text(
                    first == null
                        ? 'Llegás ${tripClock(trip.end)}'
                        : 'Sale ${tripClock(first.departure)} · llegás '
                              '${tripClock(trip.end)}',
                    style: TimbreText.caption,
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onSteps, child: const Text('Pasos')),
            IconButton(
              tooltip: 'Cerrar el viaje',
              onPressed: onClose,
              icon: const PixelIcon(PixelGlyphs.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// The steps of the chosen trip, and whether its first bus comes with GPS:
/// the live board of the stop where it is taken.
class TripStepsSheet extends StatefulWidget {
  const TripStepsSheet({super.key, required this.chosen});

  final ChosenTrip chosen;

  @override
  State<TripStepsSheet> createState() => _TripStepsSheetState();
}

class _TripStepsSheetState extends State<TripStepsSheet> {
  // The first bus on the live board, null until it answers
  ({bool asked, BusArrival? bus}) _live = (asked: false, bus: null);

  RideLeg? get _first => widget.chosen.trip.rideLegs.firstOrNull;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  Future<void> _ask() async {
    final first = _first;
    if (first == null) return;
    final results = await MvdApiService.getBoards({first.boardStop.id});
    if (!mounted) return;
    BusArrival? bus;
    if (results[first.boardStop.id] case ApiOk<ArrivalsBoard>(:final value)) {
      bus = value.arrivals
          .where((a) => a.line == first.line && a.isRealTime)
          .firstOrNull;
    }
    setState(() => _live = (asked: true, bus: bus));
  }

  @override
  Widget build(BuildContext context) {
    final chosen = widget.chosen;
    final first = _first;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Semantics(
            header: true,
            child: Text(
              'De ${chosen.from} a ${chosen.to}',
              style: TimbreText.stopName,
            ),
          ),
          const SizedBox(height: TimbreSpace.s),
          for (final leg in chosen.trip.legs) _Step(leg: leg, to: chosen.to),
          if (first != null) ...[
            const Divider(),
            _LiveFirst(line: first.line, live: _live),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.leg, required this.to});

  final Leg leg;
  final String to;

  @override
  Widget build(BuildContext context) {
    final (Widget lead, String text) = switch (leg) {
      final WalkLeg w => (
        const PixelIcon(
          PixelGlyphs.walk,
          size: TimbreIconSize.row,
          color: TimbreColors.etiquetaCartel,
        ),
        w.metres == 0
            ? 'Ya estás en la parada'
            : 'Caminá ${w.minutes} min (${w.metres} m) hasta '
                  '${w.toStopId == null ? to : 'la parada ${w.toStopId}'}',
      ),
      final RideLeg r => (
        LineBadge(r.line, live: false, compact: true),
        'Tomá el ${r.line} a las ${tripClock(r.departure)} en la parada '
            '${r.boardStop.id} · ${r.boardStop.name}. Bajá a las '
            '${tripClock(r.arrival)} en la ${r.alightStop.id} · '
            '${r.alightStop.name} (${r.stops.length - 1} paradas).',
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 56, child: Center(child: lead)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TimbreText.body)),
        ],
      ),
    );
  }
}

/// "Con GPS: el 121 llega en 3 min" — lit only for a real GPS reading.
class _LiveFirst extends StatelessWidget {
  const _LiveFirst({required this.line, required this.live});

  final String line;
  final ({bool asked, BusArrival? bus}) live;

  @override
  Widget build(BuildContext context) {
    final bus = live.bus;
    final text = !live.asked
        ? 'Buscando el $line con GPS…'
        : bus == null
        ? 'Ahora ningún $line con GPS viene a esa parada: vale el horario.'
        : 'Con GPS: el $line llega en ${bus.etaLabel}.';
    return Row(
      children: [
        PixelIcon(
          PixelGlyphs.bus,
          size: TimbreIconSize.row,
          color: bus == null ? TimbreColors.tenue : TimbreColors.ambar,
          glow: bus != null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TimbreText.subtitle.copyWith(
              color: bus == null ? TimbreColors.tenue : TimbreColors.papel,
            ),
          ),
        ),
      ],
    );
  }
}
