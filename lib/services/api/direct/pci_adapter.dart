import '../contract_rules.dart';

/// GPS data quality per operator — the open endpoint Cómo Ir reads
/// (`pci.montevideo.gub.uy/buses/control`), no credentials — turned into
/// /v1 JSON for the direct mode.
abstract final class PciAdapter {
  static const url = 'https://pci.montevideo.gub.uy/buses/control';

  /// `[{"empresa":"CUTCSA","valor":100}, …]` as the /v1 GPS status, in the
  /// API order. Null when it is not a list or has no usable item: the
  /// proxy answers 502 then.
  static Map<String, Object?>? controlToV1(Object? raw,
      {required DateTime fetchedAt}) {
    if (raw is! List) return null;
    final operators = raw.map(ContractRules.gpsOperator).nonNulls.toList();
    if (operators.isEmpty) return null;
    return {
      'fetchedAt': ContractRules.isoUtc(fetchedAt),
      'operators': operators,
    };
  }
}
