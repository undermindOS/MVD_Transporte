// The derivation rules of the /v1 contract against the vectors the proxy
// runs too (proxy/contract/v1/vectors, proxy/test/rules.test.js): every
// case of every file must give its `out` in Dart as in JS.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/services/api/contract_rules.dart';

import '../support/contract_cases.dart';

/// Each rule of the vector files (their `rule` field) on one `in` value,
/// as JSON.
final Map<String, Object? Function(dynamic input)> _rules = {
  'toIntLoose': ContractRules.toIntLoose,
  'trimText': (input) => ContractRules.trimText(input as String),
  'compareLines': (input) =>
      List<String>.from(input as List)..sort(ContractRules.compareLines),
  'stopName': (input) => ContractRules.stopName(input[0], input[1]),
  'arrival': (input) =>
      ContractRules.arrival(input['row'], DateTime.parse(input['fetchedAt'])),
  'newsLink': ContractRules.newsLink,
  'gpsOperator': ContractRules.gpsOperator,
  'stopId': (input) => ContractRules.isValidStopId(input as int),
  'schedulePath': (input) {
    final path = ContractRules.schedulePath(
        input['stopId'], input['day'], input['hour'], input['minute']);
    return {'proxyPath': path.proxyPath, 'directUrl': path.directUrl};
  },
};

void main() {
  final files = contractVectors();

  test('every rule has its vectors, and every vector file a rule', () {
    expect(files, isNotEmpty);
    expect(files.values.map((v) => v['rule']).toSet(), _rules.keys.toSet());
  });

  for (final MapEntry(key: name, value: file) in files.entries) {
    group(name, () {
      final rule = _rules[file['rule']];
      final cases = file['cases'] as List;
      for (var i = 0; i < cases.length; i++) {
        final input = (cases[i] as Map)['in'];
        final out = (cases[i] as Map)['out'];
        test('#$i', () {
          expect(rule, isNotNull, reason: 'no Dart rule ${file['rule']}');
          expect(canonicalJson(rule!(input)), canonicalJson(out),
              reason: 'in: ${jsonEncode(input)}');
        });
      }
    });
  }
}
