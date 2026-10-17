import 'package:flutter/material.dart';
import '../models/bus_stop.dart';
import '../models/scheduled_pass.dart';
import '../services/mvd_api_service.dart';

/// Theoretical timetable of a saved stop by day type and start time —
/// the "Elegir horario" of Cómo Ir.
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
    final primary = Theme.of(context).primaryColor;
    final stop = widget.stop;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horarios',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20)),
        centerTitle: true,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Icon(Icons.place, color: primary, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(stop.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              Text('#${stop.id}',
                  style: const TextStyle(color: Colors.black38, fontSize: 13)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<DayType>(
              segments: [
                for (final d in DayType.values)
                  ButtonSegment(value: d, label: Text(d.label)),
              ],
              selected: {_day},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                _day = s.first;
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time, size: 18),
                label: Text('Desde ${_formatTime(_time)}'),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Horarios teóricos, sin ubicación GPS',
                    style: TextStyle(color: Colors.black45, fontSize: 12)),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList(primary)),
        ],
      ),
    );
  }

  Widget _buildList(Color primary) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    // Offline must not look like "no buses"
    if (_failed) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('No se pudo cargar el horario',
              style: TextStyle(color: Colors.redAccent, fontSize: 14)),
          const SizedBox(height: 8),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ]),
      );
    }
    final passes = _passes ?? const [];
    if (passes.isEmpty) {
      return const Center(
        child: Text('Sin pasadas para este horario',
            style: TextStyle(color: Colors.black45, fontSize: 14)),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < passes.length; i++) {
      // The list continues after midnight
      if (i > 0 && passes[i].hhmm < passes[i - 1].hhmm) {
        rows.add(const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Después de medianoche',
              style: TextStyle(
                  color: Colors.black45,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ));
      }
      rows.add(_buildRow(passes[i], primary));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: rows);
  }

  Widget _buildRow(ScheduledPass p, Color primary) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(children: [
        SizedBox(
          width: 52,
          child: Text(p.time,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: primary.withAlpha(30),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(p.line,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: primary)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(p.destination,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ),
      ]),
    );
  }

  static String _formatTime(TimeOfDay t) =>
      '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
}
