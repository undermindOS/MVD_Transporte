import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/ui/spoken_text.dart';

void main() {
  test('uppercase names in title case for screen readers', () {
    expect(spokenName('PUNTA CARRETAS'), 'Punta Carretas');
    expect(spokenName('PLAZA ESPAÑA'), 'Plaza España');
  });

  test('particles stay lowercase, except as the first word', () {
    expect(spokenName('AV ITALIA y PROPIOS'), 'Av Italia y Propios');
    expect(spokenName('PLAZA DE LA INDEPENDENCIA'),
        'Plaza de la Independencia');
    expect(spokenName('LA PAZ'), 'La Paz');
  });

  test('extra spaces do not break it', () {
    expect(spokenName('CIUDAD  VIEJA'), 'Ciudad  Vieja');
    expect(spokenName(''), '');
  });
}
