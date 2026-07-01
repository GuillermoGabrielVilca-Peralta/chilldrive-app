import 'dart:ui' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:chilldrive_app/deteccion/clasificador_eventos.dart';

// Construye un YOLOResult 'person' con un bounding box normalizado dado.
YOLOResult persona({
  required double left,
  required double top,
  required double right,
  required double bottom,
}) {
  final box = Rect.fromLTRB(left, top, right, bottom);
  return YOLOResult(
    classIndex: 0,
    className: 'person',
    confidence: 0.9,
    boundingBox: box,
    normalizedBox: box,
  );
}

void main() {
  group('senalAEvento', () {
    test('luz verde → Señal Respetada', () {
      expect(ClasificadorEventos.senalAEvento('Green Light', 40), 'Señal Respetada');
    });
    test('luz roja en movimiento → Señal Ignorada', () {
      expect(ClasificadorEventos.senalAEvento('Red Light', 20), 'Señal Ignorada');
    });
    test('luz roja casi detenido (≤5 km/h) → Señal Respetada', () {
      expect(ClasificadorEventos.senalAEvento('Red Light', 3), 'Señal Respetada');
    });
    test('límite excedido → Exceso Velocidad', () {
      expect(ClasificadorEventos.senalAEvento('Speed Limit 40', 55), 'Exceso Velocidad');
    });
    test('dentro del límite → null', () {
      expect(ClasificadorEventos.senalAEvento('Speed Limit 40', 30), isNull);
    });
    test('clase desconocida → null', () {
      expect(ClasificadorEventos.senalAEvento('Stop Sign', 40), isNull);
    });
  });

  group('personaAEvento', () {
    test('person → Peatón Detectado', () {
      expect(ClasificadorEventos.personaAEvento('person'), 'Peatón Detectado');
    });
    test('otra clase → null', () {
      expect(ClasificadorEventos.personaAEvento('car'), isNull);
    });
  });

  group('esPositivo / esNeutro', () {
    test('Señal Respetada es positivo, no neutro', () {
      expect(ClasificadorEventos.esPositivo('Señal Respetada'), isTrue);
      expect(ClasificadorEventos.esNeutro('Señal Respetada'), isFalse);
    });
    test('Peatón Detectado es neutro, no positivo', () {
      expect(ClasificadorEventos.esNeutro('Peatón Detectado'), isTrue);
      expect(ClasificadorEventos.esPositivo('Peatón Detectado'), isFalse);
    });
    test('Frenado Brusco no es ni positivo ni neutro', () {
      expect(ClasificadorEventos.esPositivo('Frenado Brusco'), isFalse);
      expect(ClasificadorEventos.esNeutro('Frenado Brusco'), isFalse);
    });
  });

  group('mensajeRiesgoPeatonal', () {
    test('sin personas → null', () {
      expect(ClasificadorEventos.mensajeRiesgoPeatonal([], 40), isNull);
    });
    test('casi detenido (<2 km/h) → null aunque haya personas', () {
      final p = persona(left: 0.4, top: 0.2, right: 0.6, bottom: 0.75);
      expect(ClasificadorEventos.mensajeRiesgoPeatonal([p], 1), isNull);
    });
    test('3+ personas a velocidad alta → zona transitada', () {
      final ps = List.generate(
          3, (_) => persona(left: 0.4, top: 0.4, right: 0.6, bottom: 0.5));
      expect(ClasificadorEventos.mensajeRiesgoPeatonal(ps, 30),
          'Zona muy transitada. Reduce la velocidad');
    });
    test('3+ personas a baja velocidad → null', () {
      final ps = List.generate(
          3, (_) => persona(left: 0.4, top: 0.4, right: 0.6, bottom: 0.5));
      expect(ClasificadorEventos.mensajeRiesgoPeatonal(ps, 10), isNull);
    });
    test('persona muy cerca y centrada a alta velocidad → frena ahora', () {
      // altura 0.55 (>0.48 muy cercano), centrada → 4 pts; kmh>35 && pts>=2
      final p = persona(left: 0.4, top: 0.2, right: 0.6, bottom: 0.75);
      expect(ClasificadorEventos.mensajeRiesgoPeatonal([p], 45),
          '¡Atención! Persona en la vía. Frena ahora');
    });
    test('persona muy cerca y centrada a baja velocidad → reduce', () {
      final p = persona(left: 0.4, top: 0.2, right: 0.6, bottom: 0.75);
      expect(ClasificadorEventos.mensajeRiesgoPeatonal([p], 15),
          'Persona muy cerca en la vía. Reduce la velocidad');
    });
    test('persona en el borde (vereda) → null', () {
      // centerX 0.9 fuera de [0.2, 0.8] → 0 pts
      final p = persona(left: 0.85, top: 0.2, right: 0.95, bottom: 0.75);
      expect(ClasificadorEventos.mensajeRiesgoPeatonal([p], 40), isNull);
    });
  });
}
