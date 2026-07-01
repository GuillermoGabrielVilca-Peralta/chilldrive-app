import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Configuración global de la app ChillDrive.
///
/// La URL del backend ([apiBaseUrl]) puede cambiarse en tiempo de ejecución
/// desde la pantalla de Configuración (útil al cambiar de WiFi, sin recompilar).
/// Se persiste en el dispositivo y se recarga al arrancar en [cargarOverride].
class AppConfig {
  AppConfig._();

  static const _storage = FlutterSecureStorage();

  /// Clave de almacenamiento del override de URL. Pública para que `logout`
  /// (que hace `deleteAll`) pueda preservarla y no perder la config de red.
  static const String storageKey = 'apiBaseUrl';

  /// URL usada si el usuario nunca configuró una manualmente.
  /// PC y celular deben estar en el mismo WiFi; backend escuchando en 0.0.0.0:5126.
  static const String apiBaseUrlPorDefecto = 'http://10.94.71.94:5126';

  /// URL base activa. Arranca con el valor por defecto y se sobreescribe en
  /// `main()` con el override guardado (si existe).
  static String apiBaseUrl = apiBaseUrlPorDefecto;

  /// Carga la URL guardada en el dispositivo (si hay). Llamar antes de runApp.
  static Future<void> cargarOverride() async {
    final guardada = await _storage.read(key: storageKey);
    if (guardada != null && guardada.trim().isNotEmpty) {
      apiBaseUrl = guardada.trim();
    }
  }

  /// Persiste una nueva URL base y la activa en memoria.
  static Future<void> guardar(String url) async {
    apiBaseUrl = url.trim();
    await _storage.write(key: storageKey, value: apiBaseUrl);
  }

  /// Vuelve a la URL compilada por defecto y borra el override.
  static Future<void> restablecer() async {
    apiBaseUrl = apiBaseUrlPorDefecto;
    await _storage.delete(key: storageKey);
  }
}
