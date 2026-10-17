class BusArrival {
  final String line;
  final int companyCode;
  final int etaMinutes;
  final int etaSeconds;
  final double? busLatitude;
  final double? busLongitude;

  /// Variant destination (e.g. "PLAZA ESPAÑA").
  final String destination;

  /// true = ETA computed from the bus GPS position;
  /// false = timetable estimate (bus not tracked yet).
  final bool isRealTime;

  /// Scheduled pass time ("8:07"), when the API provides it.
  final String? scheduledTime;

  /// Wheelchair-accessible bus (API `accesibilidad`).
  final bool accessible;

  /// API `tipoAccesibilidad`: Cómo Ir shows the "universal accessibility"
  /// icon for 2 and the plain accessibility icon for 3; 1 = not accessible,
  /// 0 = unknown (timetable queries).
  final int? accessibilityType;

  const BusArrival({
    required this.line,
    required this.companyCode,
    required this.etaMinutes,
    required this.etaSeconds,
    this.busLatitude,
    this.busLongitude,
    this.destination = '',
    this.isRealTime = true,
    this.scheduledTime,
    this.accessible = false,
    this.accessibilityType,
  });

  String get companyName {
    switch (companyCode) {
      case 10:
        return 'COETC';
      case 20:
        return 'COME';
      case 50:
        return 'CUTCSA';
      case 70:
        return 'UCOT';
      default:
        return 'STM';
    }
  }

  String get etaLabel {
    // Timetable estimate: show the clock time, not a countdown that looks live
    if (!isRealTime && scheduledTime != null) return scheduledTime!;
    if (etaMinutes <= 0) return 'Llegando';
    if (etaMinutes == 1) return '1 min';
    return '$etaMinutes min';
  }
}
