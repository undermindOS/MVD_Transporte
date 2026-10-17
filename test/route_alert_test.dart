import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/models/route_alert.dart';

void main() {
  RouteAlert route(List<String> lines) => RouteAlert(
        id: 1,
        originStopId: 3140,
        originName: 'Origen',
        destinationName: 'Centro',
        preferredLines: lines,
      );

  test('empty preferred lines accept every line', () {
    expect(route([]).acceptsLine('145'), isTrue);
  });

  test('line match ignores case', () {
    expect(route(['64d']).acceptsLine('64D'), isTrue);
    expect(route(['G8']).acceptsLine('g8'), isTrue);
  });

  test('other lines are rejected', () {
    expect(route(['183']).acceptsLine('185'), isFalse);
  });
}
