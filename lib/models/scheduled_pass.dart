/// Timetable day type of `siguientesParada/{parada}/{tipoDia}/{H:MM}`.
enum DayType {
  habil('HABIL', 'weekday', 'Hábiles'),
  sabado('SABADO', 'saturday', 'Sábados'),
  domingo('DOMINGO', 'sunday', 'Domingos');

  final String apiValue;

  /// Same day type in the proxy route `/v1/stops/{id}/schedule/{day}/{H:MM}`.
  final String proxyValue;
  final String label;

  const DayType(this.apiValue, this.proxyValue, this.label);

  /// Same rule as Cómo Ir (holidays are not taken into account).
  static DayType of(DateTime date) => switch (date.weekday) {
        DateTime.saturday => DayType.sabado,
        DateTime.sunday => DayType.domingo,
        _ => DayType.habil,
      };
}

/// One theoretical pass of the stop timetable (no GPS involved).
class ScheduledPass {
  final String line;
  final String destination;

  /// Clock time as the API writes it ("8:03", "0:17").
  final String time;

  /// Same time as H*100+MM (803, 17) — the list wraps past midnight.
  final int hhmm;

  const ScheduledPass({
    required this.line,
    required this.destination,
    required this.time,
    required this.hhmm,
  });
}
