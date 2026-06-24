import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../api_service.dart';

/// Orquesta CUÁNDO vaciar la bandeja local de eventos (`OutboxDb`) hacia el
/// backend. El envío en sí vive en `ApiService.sincronizarPendientes`; aquí solo
/// decidimos el momento:
///
///   - al iniciar (app recién abierta),
///   - al recuperar señal (escucha de `connectivity_plus`),
///   - y, si sigue fallando, con reintentos espaciados (backoff) hasta lograrlo.
///
/// Pensado para rutas de provincia sin internet: los eventos detectados quedan
/// en la cola local y este servicio los reenvía solos cuando vuelve la señal.
class SyncService {
  SyncService(this._api);

  final ApiService _api;

  /// Espera creciente entre reintentos cuando el envío sigue fallando (segundos).
  static const _backoff = [5, 15, 30, 60];

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _reintento;
  bool _sincronizando = false;
  int _fallosSeguidos = 0;

  /// Empieza a escuchar conectividad e intenta una primera sincronización.
  void iniciar() {
    _connSub ??= Connectivity().onConnectivityChanged.listen((resultados) {
      final hayRed = resultados.any((r) => r != ConnectivityResult.none);
      if (hayRed) {
        _fallosSeguidos = 0; // recuperó señal → reinicia el backoff
        _sincronizar();
      }
    });
    _sincronizar();
  }

  /// Detiene escuchas y timers. Llamar al cerrar sesión / salir.
  void detener() {
    _connSub?.cancel();
    _connSub = null;
    _reintento?.cancel();
    _reintento = null;
  }

  /// Dispara una sincronización inmediata (p. ej. tras finalizar un viaje).
  void sincronizarAhora() => _sincronizar();

  Future<void> _sincronizar() async {
    if (_sincronizando) return; // evita solapar intentos
    _sincronizando = true;
    _reintento?.cancel();
    try {
      final restantes = await _api.sincronizarPendientes();
      if (restantes > 0) {
        _programarReintento(); // siguen fallando → reintentar con backoff
      } else {
        _fallosSeguidos = 0; // todo sincronizado (o nada pendiente)
      }
    } catch (_) {
      _programarReintento();
    } finally {
      _sincronizando = false;
    }
  }

  void _programarReintento() {
    final i =
        _fallosSeguidos < _backoff.length ? _fallosSeguidos : _backoff.length - 1;
    _fallosSeguidos++;
    _reintento = Timer(Duration(seconds: _backoff[i]), _sincronizar);
  }
}
