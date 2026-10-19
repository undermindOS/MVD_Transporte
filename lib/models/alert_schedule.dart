/// Days and hours when a periodic alert (stop or route) may notify,
/// e.g. Monday to Friday 7:30–8:30. The default is "always".
class AlertSchedule {
  static const allDays = [1, 2, 3, 4, 5, 6, 7];
  static const dayMinutes = 24 * 60;
  static const always = AlertSchedule();

  /// [DateTime.monday] .. [DateTime.sunday]
  final List<int> days;

  /// Minutes since midnight; the window is [fromMinute, toMinute).
  /// toMinute < fromMinute runs past midnight (22:00–1:00).
  final int fromMinute;
  final int toMinute;

  const AlertSchedule({
    this.days = allDays,
    this.fromMinute = 0,
    this.toMinute = dayMinutes,
  });

  bool get isAllDay => fromMinute == 0 && toMinute == dayMinutes;

  bool get isAlways => isAllDay && allDays.every(days.contains);

  bool allows(DateTime time) {
    final minute = time.hour * 60 + time.minute;
    if (fromMinute <= toMinute) {
      return days.contains(time.weekday) &&
          minute >= fromMinute &&
          minute < toMinute;
    }
    // Past midnight: the early hours belong to the day the window started
    if (minute >= fromMinute) return days.contains(time.weekday);
    if (minute < toMinute) {
      return days.contains(time.weekday == DateTime.monday
          ? DateTime.sunday
          : time.weekday - 1);
    }
    return false;
  }

  static const dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  static String time(int minute) =>
      '${minute ~/ 60 % 24}:${(minute % 60).toString().padLeft(2, '0')}';

  /// "Siempre", "Lun a Vie 7:30–8:30", "Sáb, Dom", "22:00–1:00"
  String get label {
    if (isAlways) return 'Siempre';
    final sorted = [...days]..sort();
    final String dayText;
    if (sorted.length == 7) {
      dayText = '';
    } else if (sorted.length >= 3 &&
        sorted.last - sorted.first == sorted.length - 1) {
      dayText = '${dayNames[sorted.first - 1]} a ${dayNames[sorted.last - 1]}';
    } else {
      dayText = sorted.map((d) => dayNames[d - 1]).join(', ');
    }
    final hours = isAllDay ? '' : '${time(fromMinute)}–${time(toMinute)}';
    return [dayText, hours].where((s) => s.isNotEmpty).join(' ');
  }
}
