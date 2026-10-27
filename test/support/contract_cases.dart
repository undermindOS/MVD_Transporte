import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Contract test support: the /v1 contract shared with the proxy
// (proxy/contract/v1/README.md) — its cases, goldens, upstream captures and
// vectors. Read by relative path: run `flutter test` from the repo root.

/// The contract folder, from the repo root.
const contractDir = 'proxy/contract/v1';

/// Where the proxy-mode cases send their requests.
const proxyBase = 'https://proxy.test';

/// `fetchedAt` as the contract writes it: ISO 8601 UTC with milliseconds.
final isoMillis = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');

/// A contract file, as bytes: served as UTF-8 bytes, never as a `String`
/// (`http.Response` would encode it as latin1).
List<int> contractBytes(String path) =>
    File('$contractDir/$path').readAsBytesSync();

/// A contract file, decoded.
Object? contractJson(String path) =>
    jsonDecode(File('$contractDir/$path').readAsStringSync());

/// The masks a case may apply to a golden in direct mode
/// (`direct_masks.json`).
List<String> contractMasks() =>
    List<String>.from(contractJson('direct_masks.json') as List);

/// The vector files (`vectors/*.json`), by file name.
Map<String, Map<String, Object?>> contractVectors() {
  final files = Directory('$contractDir/vectors')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final f in files)
      f.uri.pathSegments.last:
          jsonDecode(f.readAsStringSync()) as Map<String, Object?>,
  };
}

/// What the direct mode must do with a case: request exactly [upstream],
/// then give the golden with [mask] applied, or [failure].
typedef DirectExpectation = ({
  List<String> upstream,
  List<String> mask,
  String? failure,
});

/// What the app must make of the proxy's answer: the model, or [failure]
/// with [retryAfter] seconds. [request] false: no request in either mode.
typedef DartExpectation = ({String? failure, int? retryAfter, bool request});

/// One entry of `cases.json` (format in proxy/contract/v1/README.md).
class ContractCase {
  final String id;

  /// The /v1 path the app requests, always with GET.
  final String request;

  /// The proxy's answer: [status], [headers] and the golden at [response].
  final int status;
  final Map<String, String> headers;
  final String response;

  /// The requests the proxy makes, with their answers; the direct mode is
  /// served from the same entries.
  final List<Map<String, Object?>> upstream;

  /// Null: no direct-mode equivalent.
  final DirectExpectation? direct;

  /// Null: the app never builds this request.
  final DartExpectation? dart;

  ContractCase.fromJson(Map<String, Object?> json)
      : id = json['id'] as String,
        request = json['request'] as String,
        status = json['status'] as int,
        headers = (json['headers'] as Map).map(
            (name, value) => MapEntry('$name'.toLowerCase(), '$value')),
        response = json['response'] as String,
        upstream = [
          for (final e in json['upstream'] as List)
            (e as Map).cast<String, Object?>(),
        ],
        direct = switch (json['direct']) {
          final Map d => (
              upstream: List<String>.from(d['upstream'] as List),
              mask: List<String>.from(d['mask'] as List),
              failure: d['failure'] as String?,
            ),
          _ => null,
        },
        dart = switch (json['dart']) {
          final Map d => (
              failure: d['failure'] as String?,
              retryAfter: d['retryAfter'] as int?,
              request: d['request'] != false,
            ),
          _ => null,
        };

  /// The golden body, decoded.
  Object? get golden => contractJson(response);

  @override
  String toString() => id;
}

/// Every case of `cases.json`, in file order.
List<ContractCase> contractCases() => [
      for (final c in contractJson('cases.json') as List)
        ContractCase.fromJson((c as Map).cast<String, Object?>()),
    ];

/// The city's servers as [c] describes them: each `upstream` entry at its
/// exact URL, as often as it is asked. Every request URL is added to
/// [requested]; a URL the case does not list gets a 404, so the URL check
/// names it.
MockClient upstreamClient(ContractCase c, List<String> requested) {
  final byUrl = {for (final e in c.upstream) e['url'] as String: e};
  return MockClient((request) async {
    final url = '${request.url}';
    requested.add(url);
    final entry = byUrl[url];
    if (entry == null) return http.Response('not in ${c.id}', 404);
    if (entry['throw'] == 'timeout') throw TimeoutException(url);
    final body = entry.containsKey('file')
        ? contractBytes(entry['file'] as String)
        : utf8.encode(entry['body'] as String);
    return http.Response.bytes(body, (entry['status'] as int?) ?? 200,
        headers: {
          for (final h in ((entry['headers'] as Map?) ?? const {}).entries)
            '${h.key}'.toLowerCase(): '${h.value}',
        });
  });
}

/// The proxy as [c] describes it: the golden with the case's status and
/// headers, at `$proxyBase{request}` only. Every request URL is added to
/// [requested]; any other URL gets a 404.
MockClient proxyClient(ContractCase c, List<String> requested) {
  final golden = contractBytes(c.response);
  return MockClient((request) async {
    final url = '${request.url}';
    requested.add(url);
    if (url != '$proxyBase${c.request}') {
      return http.Response('{"error":"not_found"}', 404);
    }
    return http.Response.bytes(golden, c.status, headers: {
      'content-type': 'application/json; charset=utf-8',
      ...c.headers,
    });
  });
}

/// [golden] as the direct mode gives it (README, "Máscaras"):
/// `list[].field` sets that field of every item of `list` to null; `field`
/// sets a list to `[]` and anything else to null.
Object? applyMask(Object? golden, List<String> masks) {
  final body = jsonDecode(jsonEncode(golden)) as Map<String, Object?>;
  for (final mask in masks) {
    final dot = mask.indexOf('[].');
    if (dot >= 0) {
      final field = mask.substring(dot + 3);
      for (final item in body[mask.substring(0, dot)] as List) {
        (item as Map)[field] = null;
      }
    } else {
      body[mask] = body[mask] is List ? <Object?>[] : null;
    }
  }
  return body;
}

/// [json] without its top-level `fetchedAt`, which is compared apart.
Object? withoutFetchedAt(Object? json) {
  if (json is! Map) return json;
  return Map<String, Object?>.from(json)..remove('fetchedAt');
}

/// [json] as indented text with every object's keys sorted: equal texts
/// mean the same JSON, numbers included (5 is not 5.0), whatever the key
/// order.
String canonicalJson(Object? json) =>
    const JsonEncoder.withIndent(' ').convert(_sorted(json));

Object? _sorted(Object? json) => switch (json) {
      final Map map => {
          for (final key in map.keys.map((k) => '$k').toList()..sort())
            key: _sorted(map[key]),
        },
      final List list => [for (final item in list) _sorted(item)],
      _ => json,
    };
