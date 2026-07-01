import 'package:flutter_test/flutter_test.dart';
import 'package:chilldrive_app/utils/racha.dart';

void main() {
  group('diaPeruDeIso', () {
    test('UTC de madrugada cae en el día anterior en Perú', () {
      // 02:00 UTC del 1-jul = 21:00 (día 30) en Perú (UTC-5).
      expect(diaPeruDeIso('2026-07-01T02:00:00'), DateTime.utc(2026, 6, 30));
    });

    test('UTC de mediodía cae en el mismo día en Perú', () {
      // 12:00 UTC = 07:00 Perú → mismo día.
      expect(diaPeruDeIso('2026-07-01T12:00:00'), DateTime.utc(2026, 7, 1));
    });

    test('con sufijo Z da el mismo resultado', () {
      expect(diaPeruDeIso('2026-07-01T02:00:00Z'), DateTime.utc(2026, 6, 30));
    });

    test('null / vacío / inválido → null', () {
      expect(diaPeruDeIso(null), isNull);
      expect(diaPeruDeIso(''), isNull);
      expect(diaPeruDeIso('no-es-fecha'), isNull);
    });
  });

  group('calcularRacha', () {
    final hoy = DateTime.utc(2026, 7, 10);
    DateTime dia(int d) => DateTime.utc(2026, 7, d);

    test('sin días → 0', () {
      expect(calcularRacha({}, hoy), 0);
    });

    test('solo hoy → 1', () {
      expect(calcularRacha({dia(10)}, hoy), 1);
    });

    test('solo ayer (aún no condujo hoy) → 1', () {
      expect(calcularRacha({dia(9)}, hoy), 1);
    });

    test('tres días consecutivos hasta hoy → 3', () {
      expect(calcularRacha({dia(10), dia(9), dia(8)}, hoy), 3);
    });

    test('hueco ayer rompe la racha → solo cuenta hoy', () {
      // Tiene hoy y antier, pero falta ayer → la cadena se corta en hoy.
      expect(calcularRacha({dia(10), dia(8)}, hoy), 1);
    });

    test('último viaje hace 3 días (ni hoy ni ayer) → 0', () {
      expect(calcularRacha({dia(7)}, hoy), 0);
    });

    test('racha que termina ayer también cuenta', () {
      // Condujo ayer, antier y hace 3 días, pero no hoy → racha 3 (parte de ayer).
      expect(calcularRacha({dia(9), dia(8), dia(7)}, hoy), 3);
    });
  });
}
