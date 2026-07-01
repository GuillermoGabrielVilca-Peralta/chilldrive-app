import 'package:flutter_test/flutter_test.dart';
import 'package:chilldrive_app/utils/geo.dart';

void main() {
  group('distanciaHaversineKm', () {
    test('mismo punto da 0', () {
      expect(distanciaHaversineKm(-16.43, -71.52, -16.43, -71.52), 0);
    });

    test('un grado de latitud ≈ 111 km', () {
      final d = distanciaHaversineKm(0, 0, 1, 0);
      expect(d, closeTo(111.19, 0.5));
    });

    test('Lima → Arequipa ≈ 760 km en línea recta', () {
      // Lima (-12.046, -77.043) → Arequipa (-16.409, -71.537)
      final d = distanciaHaversineKm(-12.046, -77.043, -16.409, -71.537);
      expect(d, closeTo(760, 30));
    });
  });

  group('distanciaKmDeRecorrido', () {
    test('lista vacía da 0', () {
      expect(distanciaKmDeRecorrido([]), 0);
    });

    test('un solo punto da 0', () {
      expect(distanciaKmDeRecorrido([
        [-16.43, -71.52, 30],
      ]), 0);
    });

    test('suma los tramos consecutivos e ignora la velocidad', () {
      // Tres puntos en línea, ~1 grado de separación cada uno (~111 km × 2).
      final total = distanciaKmDeRecorrido([
        [0, 0, 0],
        [1, 0, 40],
        [2, 0, 50],
      ]);
      expect(total, closeTo(222.38, 1));
    });
  });
}
