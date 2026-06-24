/// Configuración global de la app ChillDrive.
/// Cambiar [apiBaseUrl] aquí para apuntar a otro entorno
/// (producción, otra IP de LAN, staging).
class AppConfig {
  AppConfig._();

  /// URL base del backend. PC y celular deben estar en el mismo WiFi.
  /// Usar el perfil `lan` de Rider para que el backend escuche en 0.0.0.0:5126.
  static const String apiBaseUrl = 'http://10.32.166.94:5126';
}
