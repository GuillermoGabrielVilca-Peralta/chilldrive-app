import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

/// Detecta tres tipos de maniobras bruscas durante un viaje:
///
///   - **Frenado brusco**: caída rápida de velocidad GPS + pico en el acelerómetro.
///   - **Aceleración brusca**: subida rápida de velocidad GPS + pico en el acelerómetro.
///   - **Giro brusco**: cambio rápido de rumbo (heading) del GPS a velocidad sostenida.
///
/// Usar la magnitud del vector acelerómetro (no un eje fijo) y confirmar siempre
/// con la velocidad GPS hace que funcione sin importar cómo esté montado el teléfono,
/// y descarta falsos positivos por baches o vibraciones.
class DetectorConduccion {
  DetectorConduccion({
    required this.velocidadKmh,
    required this.headingDeg,
    required this.onFrenadoBrusco,
    required this.onAceleracionBrusca,
    required this.onGiroBrusco,
  });

  /// Velocidad actual en km/h.
  final double Function() velocidadKmh;

  /// Rumbo actual en grados (0–360, del GPS). Usado para detectar giros.
  final double Function() headingDeg;

  final void Function() onFrenadoBrusco;
  final void Function() onAceleracionBrusca;
  final void Function() onGiroBrusco;

  // ── Umbrales (ajustables según pruebas en carretera) ──────────────────────

  /// Pico de acelerómetro considerado "brusco" (m/s²). ~0.35 g.
  static const double _umbralAcel = 3.5;

  /// Velocidad mínima para evaluar cualquier evento (km/h).
  static const double _velMinima = 12;

  /// Caída/subida de velocidad en la ventana para confirmar frenado/aceleración.
  static const double _deltaVelMin = 7;

  /// Cambio de rumbo en la ventana para confirmar un giro brusco (grados).
  static const double _deltaRumboMin = 25;

  /// Velocidad mínima para detectar giros (km/h).
  /// 45 km/h descarta giros normales en ciudad (esquinas, rotondas a baja velocidad).
  static const double _velMinimaGiro = 45;

  /// Ventana de historial que se conserva para medir la tendencia.
  static const Duration _ventana = Duration(seconds: 2);

  /// Historial mínimo acumulado antes de evaluar (evita disparos al inicio).
  static const Duration _ventanaMinima = Duration(milliseconds: 800);

  /// Cooldown individual por tipo de evento (no molesta dos veces seguidas).
  static const Duration _cooldown = Duration(seconds: 6);

  /// Frecuencia de muestreo (20 Hz — suficiente y ahorra batería).
  static const Duration _muestreo = Duration(milliseconds: 50);

  /// Muestras consecutivas por encima del umbral requeridas para confirmar un pico.
  /// 3 muestras × 50 ms = 150 ms — filtra baches y vibraciones puntuales.
  static const int _muestrasMinimas = 3;

  StreamSubscription<UserAccelerometerEvent>? _sub;
  final List<_Muestra> _historial = [];
  int _muestrasEnPico = 0;

  DateTime _ultimoFrenado       = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _ultimoAceleracion   = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _ultimoGiro          = DateTime.fromMillisecondsSinceEpoch(0);

  void iniciar() {
    _sub ??= userAccelerometerEventStream(samplingPeriod: _muestreo)
        .listen(_onAceleracion);
  }

  void detener() {
    _sub?.cancel();
    _sub = null;
    _historial.clear();
    _muestrasEnPico = 0;
  }

  void _onAceleracion(UserAccelerometerEvent e) {
    final ahora  = DateTime.now();
    final vel    = velocidadKmh();
    final rumbo  = headingDeg();

    // Mantener ventana deslizante.
    _historial.add(_Muestra(ahora, vel, rumbo));
    _historial.removeWhere((m) => ahora.difference(m.t) > _ventana);

    if (vel < _velMinima) return;

    final primero = _historial.first;
    if (ahora.difference(primero.t) < _ventanaMinima) return;

    // ── Giro brusco (cambio de rumbo GPS) ───────────────────────────────────
    // Independiente del acelerómetro: solo depende de velocidad y rumbo del GPS,
    // por eso se evalúa ANTES del filtro de pico longitudinal. Un giro a velocidad
    // constante no genera pico de frenado/aceleración pero sí cambio de rumbo.
    if (vel >= _velMinimaGiro &&
        ahora.difference(_ultimoGiro) >= _cooldown) {
      final deltaRumbo = _diffAngular(primero.rumbo, rumbo);
      if (deltaRumbo >= _deltaRumboMin) {
        _ultimoGiro = ahora;
        onGiroBrusco();
      }
    }

    // ── Filtro de pico longitudinal (solo frenado / aceleración) ────────────
    // Cuenta muestras consecutivas sobre el umbral; un bache (pico de 1 muestra
    // ~50 ms) no alcanza el mínimo y se descarta.
    final magnitud = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (magnitud >= _umbralAcel) {
      _muestrasEnPico++;
    } else {
      _muestrasEnPico = 0;
    }
    if (_muestrasEnPico < _muestrasMinimas) return;

    // ── Frenado brusco ──────────────────────────────────────────────────────
    if (ahora.difference(_ultimoFrenado) >= _cooldown) {
      final deltaVel = primero.v - vel; // positivo = velocidad cayó
      if (deltaVel >= _deltaVelMin) {
        _ultimoFrenado = ahora;
        onFrenadoBrusco();
        return;
      }
    }

    // ── Aceleración brusca ──────────────────────────────────────────────────
    if (ahora.difference(_ultimoAceleracion) >= _cooldown) {
      final deltaVel = vel - primero.v; // positivo = velocidad subió
      if (deltaVel >= _deltaVelMin) {
        _ultimoAceleracion = ahora;
        onAceleracionBrusca();
      }
    }
  }

  /// Diferencia angular mínima entre dos rumbos en grados (0–180).
  static double _diffAngular(double a, double b) {
    final d = (b - a).abs() % 360;
    return d > 180 ? 360 - d : d;
  }
}

class _Muestra {
  _Muestra(this.t, this.v, this.rumbo);
  final DateTime t;
  final double v;
  final double rumbo;
}
