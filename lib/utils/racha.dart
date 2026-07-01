// Lógica pura de la racha de días (sin dependencias de UI → testeable).
//
// Los viajes guardan `fechaInicio` en UTC (el backend usa DateTime.UtcNow y lo
// serializa SIN 'Z'). Para que la racha cuadre con el criterio del backend, todo
// se lleva a día calendario en hora de Perú (UTC-5), igual que ViajeService.

const int _offsetPeruHoras = 5;

/// Día calendario en Perú (UTC-5) de un instante UTC, como fecha UTC-normalizada
/// (medianoche UTC) para que la aritmética de días no sufra el horario de verano
/// de la zona del dispositivo.
DateTime _aDiaPeru(DateTime utc) {
  final peru = utc.subtract(const Duration(hours: _offsetPeruHoras));
  return DateTime.utc(peru.year, peru.month, peru.day);
}

/// Convierte la `fechaInicio` ISO de un viaje a su día calendario en Perú.
/// Trata la marca como UTC (venga con 'Z' o sin él). Null si es inválida.
DateTime? diaPeruDeIso(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return null;
  // Sin 'Z', Dart la parsea como local; reinterpretamos los componentes como UTC.
  final utc = parsed.isUtc
      ? parsed
      : DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
          parsed.minute, parsed.second, parsed.millisecond);
  return _aDiaPeru(utc);
}

/// Día de hoy en Perú (para pasar a [calcularRacha]).
DateTime hoyEnPeru() => _aDiaPeru(DateTime.now().toUtc());

/// Racha de días consecutivos con actividad que termina en HOY o AYER (no penaliza
/// si aún no condujo hoy). [dias] son días calendario (de [diaPeruDeIso]); [hoy] es
/// el día actual en Perú (de [hoyEnPeru]). Cuenta hacia atrás hasta el primer hueco.
int calcularRacha(Set<DateTime> dias, DateTime hoy) {
  if (dias.isEmpty) return 0;

  var diaCheck = hoy;
  // Acepta ayer como punto de partida si aún no condujo hoy.
  if (!dias.contains(diaCheck)) {
    diaCheck = diaCheck.subtract(const Duration(days: 1));
  }

  var racha = 0;
  while (dias.contains(diaCheck)) {
    racha++;
    diaCheck = diaCheck.subtract(const Duration(days: 1));
  }
  return racha;
}
