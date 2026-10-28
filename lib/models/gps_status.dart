/// Share of an operator's buses whose GPS data is reaching the system
/// (/v1 `GpsStatusResponse`).
class OperatorGpsStatus {
  /// Below this Cómo Ir stops showing the operator as OK.
  static const partialThreshold = 70;

  final String company;

  /// 0–100.
  final int percent;

  /// As the source decided; null = derived from [percent].
  final bool? partial;

  const OperatorGpsStatus(this.company, this.percent, {this.partial});

  bool get isPartial => partial ?? percent < partialThreshold;
}
