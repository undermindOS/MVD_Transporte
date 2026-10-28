import 'package:flutter/material.dart';
import '../models/bus_stop.dart';
import '../models/scheduled_pass.dart';
import '../services/mvd_api_service.dart';
import 'spoken_text.dart';
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/empty_state.dart';
import 'widgets/line_badge.dart';
import 'widgets/pixel_icon.dart';
import 'widgets/segmented.dart';
import 'widgets/timbre_app_bar.dart';

/// Theoretical timetable of a saved stop by day type and start time —
/// the "Elegir horario" of Cómo Ir. Timetable data never uses the LED
/// cartel or dot-matrix digits: no GPS is involved.
class SchedulePage extends StatefulWidget {
  final BusStop stop;

  /// Defaults to now; injectable for tests.
  final DateTime? now;

  /// Defaults to [MvdApiService.getSchedule]; injectable for tests.
  final Future<List<ScheduledPass>?> Function(
      int stopId, DayType day, int hour, int minute)? fetch;

  const SchedulePage({super.key, required this.stop, this.now, this.fetch});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late DayType _day;
  late TimeOfDay _time;
  List<ScheduledPass>? _passes;
  bool _loading = false;
  bool _failed = false;
  // Drops answers of superseded requests (fast day/time changes)
  int _request = 0;

  static const _stopLine = TextStyle(
    fontFamily: TimbreFonts.firaCondensed,
    fontWeight: FontWeight.w700,
    fontSize: 17,
    height: 1.2,
    color: TimbreColors.etiquetaCartel,
  );

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    _day = DayType.of(now);
    // Like Cómo Ir: start at the current time rounded down to 5 minutes
    _time = TimeOfDay(hour: now.hour, minute: now.minute - now.minute % 5);
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final passes = await (widget.fetch ?? MvdApiService.getSchedule)(
        widget.stop.id, _day, _time.hour, _time.minute);
    if (!mounted || request != _request) return;
    setState(() {
      _passes = passes;
      _failed = passes == null;
      _loading = false;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || picked == _time) return;
    _time = picked;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final stop = widget.stop;

    return Scaffold(
      backgroundColor: TimbreColors.noche,
      // The identity bar of the tabs; a long stop name takes a second
      // line, the stop number is never cut
      appBar: buildTimbreAppBar(
        context,
        title: 'Horarios',
        subtitle: stop.name,
        subtitleTrailing: ' · ${stop.id}',
        subtitleStyle: _stopLine,
        semanticLabel:
            'Horarios de la parada ${stop.id}, ${spokenName(stop.name)}',
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: const BoxDecoration(
              color: TimbreColors.noche,
              border: Border(bottom: BorderSide(color: TimbreColors.lineaNoche)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TimbreSegmented<DayType>(
                  values: DayType.values,
                  selected: _day,
                  labelOf: (d) => d.label,
                  semanticLabel: 'Tipo de día',
                  onChanged: (d) {
                    _day = d;
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const PixelIcon(PixelGlyphs.clock,
                        size: TimbreIconSize.row),
                    label: Text('Desde ${_formatTime(_time)}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TimbreColors.ambar,
                      minimumSize: const Size(0, TimbreSpace.touch),
                      padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
                      side: const BorderSide(
                          color: TimbreColors.ambarTenue, width: 1.5),
                      shape: const StadiumBorder(),
                      textStyle: TimbreText.button
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Horarios teóricos, sin ubicación GPS',
                        style: TextStyle(
                            color: TimbreColors.etiquetaCartel,
                            fontSize: 13,
                            height: 1.35)),
                  ),
                ]),
              ],
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    // Offline must not look like "no buses"; an error is a red LED
    if (_failed) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const PixelIcon(PixelGlyphs.warning,
              size: TimbreIconSize.rowLarge, color: TimbreColors.rojoLed),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TimbreSpace.xl),
            child: Text('No se pudo cargar el horario. Revisá la conexión.',
                textAlign: TextAlign.center,
                style: TimbreText.body.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ]),
      );
    }
    final passes = _passes ?? const [];
    if (passes.isEmpty) {
      return const Center(
        child: SingleChildScrollView(
          child: TimbreEmptyState('Sin pasadas para este horario',
              sign: 'SIN PASADAS',
              detail: 'Probá con otro día o con una hora más temprano.'),
        ),
      );
    }

    final rows = <Widget>[];
    int? hour;
    for (var i = 0; i < passes.length; i++) {
      // The list continues after midnight
      if (i > 0 && passes[i].hhmm < passes[i - 1].hhmm) {
        rows.add(const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text('Después de medianoche',
              style: TextStyle(
                  color: TimbreColors.etiquetaCartel,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ));
        hour = null;
      }
      final h = passes[i].hhmm ~/ 100;
      if (h != hour) {
        rows.add(_HourHeader(h));
        hour = h;
      }
      rows.add(_PassRow(passes[i]));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: rows);
  }

  static String _formatTime(TimeOfDay t) =>
      '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
}

class _HourHeader extends StatelessWidget {
  const _HourHeader(this.hour);

  final int hour;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'Las $hour',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        decoration: const BoxDecoration(
          color: TimbreColors.tinta,
          border: Border(bottom: BorderSide(color: TimbreColors.lineaNoche)),
        ),
        // A timetable is never lit: the hour is a label
        child: Text('$hour h',
            style: const TextStyle(
                fontFamily: TimbreFonts.firaCondensed,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: TimbreColors.etiquetaCartel)),
      ),
    );
  }
}

class _PassRow extends StatelessWidget {
  const _PassRow(this.pass);

  final ScheduledPass pass;

  @override
  Widget build(BuildContext context) {
    final p = pass;
    return Semantics(
      label: '${p.time}, línea ${p.line} a ${spokenName(p.destination)}',
      excludeSemantics: true,
      child: Container(
        // Grows with the system font size instead of cutting the time
        constraints: const BoxConstraints(minHeight: TimbreSpace.touch),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: TimbreColors.lineaNoche)),
        ),
        child: Row(children: [
          // Fits "23:55" at the default size; scales down rather than
          // wrapping with the largest fonts
          SizedBox(
              width: 56,
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(p.time, style: TimbreText.scheduleTime))),
          const SizedBox(width: 10),
          LineBadge(p.line, live: false, compact: true),
          const SizedBox(width: 10),
          Expanded(
            // Two lines, like the arrival rows, before anything is cut
            child: Text(p.destination,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TimbreText.destination.copyWith(fontSize: 17)),
          ),
        ]),
      ),
    );
  }
}
