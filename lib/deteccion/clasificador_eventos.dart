import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// Reglas **puras** de clasificación de detecciones → eventos de conducción.
///
/// Sin estado ni dependencias de UI/plataforma: 100% testeable. Aquí viven las
/// reglas de qué cuenta como cada evento (CLAUDE.md: las reglas de detección van
/// aquí, no en la pantalla). La pantalla solo cablea cámara/GPS/TTS y llama a
/// estos métodos.
class ClasificadorEventos {
  ClasificadorEventos._();

  /// Modo señales: clase YOLO + velocidad → `TipoEvento` del backend (o null si
  /// no aplica). Debe usar tipos presentes en `EventoService.TiposValidos` y en
  /// el CHECK `eventos.tipo_evento`.
  static String? senalAEvento(String clase, double kmh) {
    if (clase == 'Green Light') return 'Señal Respetada';
    if (clase == 'Red Light') {
      return kmh > 5 ? 'Señal Ignorada' : 'Señal Respetada';
    }
    if (clase.startsWith('Speed Limit')) {
      final limite = int.tryParse(clase.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (limite > 0 && kmh > limite) return 'Exceso Velocidad';
      return null;
    }
    return null;
  }

  /// Modo personas (COCO): solo reacciona a peatones.
  static String? personaAEvento(String clase) {
    if (clase == 'person') return 'Peatón Detectado';
    return null;
  }

  /// Eventos de buena conducta (suman puntos / alerta verde).
  static bool esPositivo(String tipo) =>
      tipo == 'Señal Respetada' ||
      tipo == 'Carril Mantenido' ||
      tipo == 'Distancia Segura';

  /// Eventos neutros (aviso de seguridad, 0 pts / alerta naranja).
  static bool esNeutro(String tipo) => tipo == 'Peatón Detectado';

  /// Evalúa si hay riesgo real de atropello según posición + tamaño del
  /// bounding box normalizado (0–1) y velocidad actual.
  /// Retorna el mensaje a hablar, o null si no hay riesgo.
  static String? mensajeRiesgoPeatonal(List<YOLOResult> personas, double kmh) {
    if (personas.isEmpty || kmh < 2) return null;

    // Muchas personas en campo: zona escolar / mercado → siempre avisar
    if (personas.length >= 3) {
      return kmh > 20
          ? 'Zona muy transitada. Reduce la velocidad'
          : null; // a velocidad muy baja no hace falta
    }

    int puntos = 0;
    for (final p in personas) {
      final box = p.normalizedBox;
      final centerX = (box.left + box.right) / 2;
      final altura  = box.height; // bottom - top (0–1)

      final centrado    = centerX >= 0.20 && centerX <= 0.80;
      final cercano     = altura > 0.28;
      final muyCercano  = altura > 0.48;

      if (muyCercano && centrado) { puntos += 4; }
      else if (cercano && centrado) { puntos += 2; }
      else if (centrado) { puntos += 1; }
      // Persona en el borde (vereda): 0 puntos → sin alerta
    }

    if (puntos == 0) return null;

    if (kmh > 35 && puntos >= 2) {
      return '¡Atención! Persona en la vía. Frena ahora';
    }
    if (puntos >= 4) {
      return 'Persona muy cerca en la vía. Reduce la velocidad';
    }
    if (puntos >= 2) {
      return 'Precaución, persona detectada en la vía';
    }
    return null;
  }
}
