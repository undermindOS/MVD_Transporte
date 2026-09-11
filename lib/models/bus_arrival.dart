class BusArrival {
  final String line;
  final int companyCode;
  final int etaMinutes;
  final int etaSeconds;
  final double? busLatitude;
  final double? busLongitude;

  const BusArrival({
    required this.line,
    required this.companyCode,
    required this.etaMinutes,
    required this.etaSeconds,
    this.busLatitude,
    this.busLongitude,
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
    if (etaMinutes <= 0) return 'Llegando';
    if (etaMinutes == 1) return '1 min';
    return '$etaMinutes min';
  }
}
