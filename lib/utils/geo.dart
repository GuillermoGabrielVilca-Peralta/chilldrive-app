import 'dart:math' as math;

/// Utilidades geográficas puras (sin dependencias de plataforma → testeables).

const double _radioTierraKm = 6371.0;

/// Distancia en kilómetros entre dos coordenadas (fórmula de Haversine).
double distanciaHaversineKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final dLat = _aRadianes(lat2 - lat1);
  final dLon = _aRadianes(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_aRadianes(lat1)) *
          math.cos(_aRadianes(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _radioTierraKm * c;
}

/// Distancia total recorrida (km) sumando los tramos entre waypoints consecutivos.
/// Cada waypoint es `[lat, lon, speed?]`; ignora la velocidad. Con menos de 2
/// puntos la distancia es 0.
double distanciaKmDeRecorrido(List<List<double>> recorrido) {
  if (recorrido.length < 2) return 0;
  var total = 0.0;
  for (var i = 0; i < recorrido.length - 1; i++) {
    final a = recorrido[i];
    final b = recorrido[i + 1];
    total += distanciaHaversineKm(a[0], a[1], b[0], b[1]);
  }
  return total;
}

double _aRadianes(double grados) => grados * math.pi / 180.0;
