import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'config/app_config.dart';
import 'data/outbox_db.dart';

class ApiService {
  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final OutboxDb _outbox = OutboxDb.instance;

  ApiService()
      : _dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        // Auto-renovación: si el access token expiró (401), intenta refrescarlo una
        // sola vez con el refresh token y reintenta la request original. Así el
        // usuario no tiene que volver a iniciar sesión cada día.
        final req = e.requestOptions;
        final es401         = e.response?.statusCode == 401;
        final esAuth        = req.path.contains('/api/auth/'); // login/refresh: no reintentar
        final yaReintentado = req.extra['reintentado'] == true;

        if (es401 && !esAuth && !yaReintentado && await _refrescarToken()) {
          final nuevoToken = await _storage.read(key: 'token');
          req.extra['reintentado'] = true;
          req.headers['Authorization'] = 'Bearer $nuevoToken';
          try {
            return handler.resolve(await _dio.fetch(req));
          } on DioException catch (err) {
            return handler.next(err);
          }
        }
        handler.next(e);
      },
    ));
  }

  /// Refresh en curso (si lo hay). Coalesce varias 401 simultáneas en una sola
  /// renovación para no disparar N llamadas a /refresh a la vez.
  Future<bool>? _refrescando;

  Future<bool> _refrescarToken() =>
      _refrescando ??= _hacerRefresh().whenComplete(() => _refrescando = null);

  /// Pide un nuevo par de tokens usando el refresh token guardado. Usa un cliente
  /// Dio limpio para evitar recursión de interceptores y no mandar el token vencido.
  Future<bool> _hacerRefresh() async {
    final refresh = await _storage.read(key: 'refreshToken');
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await Dio(BaseOptions(baseUrl: _dio.options.baseUrl))
          .post('/api/auth/refresh', data: {'refreshToken': refresh});
      final data = res.data as Map<String, dynamic>;
      await _storage.write(key: 'token', value: data['token'] as String);
      final nuevoRefresh = data['refreshToken'] as String?;
      if (nuevoRefresh != null && nuevoRefresh.isNotEmpty) {
        await _storage.write(key: 'refreshToken', value: nuevoRefresh);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Sesión ──────────────────────────────────────────────────────────────

  Future<void> login(String correo, String password) async {
    final res = await _dio.post('/api/auth/login', data: {
      'correo': correo,
      'password': password,
    });
    final data = res.data as Map<String, dynamic>;
    await _storage.write(key: 'token', value: data['token'] as String);
    await _storage.write(key: 'refreshToken', value: data['refreshToken'] as String? ?? '');
    await _storage.write(key: 'usuarioId', value: data['usuarioId'].toString());
    await _storage.write(key: 'nombreCompleto', value: data['nombreCompleto'] as String? ?? '');
    await _storage.write(key: 'tipoConductor', value: data['tipoConductor'] as String? ?? 'Particular');
  }

  Future<void> logout() async {
    // deleteAll borra TODO el almacenamiento seguro, incluida la URL del backend
    // que el usuario pudo configurar. La preservamos para no perder la red al salir.
    final urlBackend = await _storage.read(key: AppConfig.storageKey);
    await _storage.deleteAll();
    if (urlBackend != null) {
      await _storage.write(key: AppConfig.storageKey, value: urlBackend);
    }
  }

  /// URL base actual del backend (para mostrarla en Configuración).
  String get baseUrl => _dio.options.baseUrl;

  /// Cambia la URL del backend en caliente: la persiste y la aplica a este
  /// cliente sin reiniciar la app.
  Future<void> setBaseUrl(String url) async {
    await AppConfig.guardar(url);
    _dio.options.baseUrl = AppConfig.apiBaseUrl;
  }

  /// Prueba la conexión contra el endpoint público /health del backend.
  /// Devuelve true si responde 200. No lanza.
  Future<bool> probarConexion() async {
    try {
      final res = await _dio.get('/health');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> get isLoggedIn async => (await _storage.read(key: 'token')) != null;

  Future<int> getUsuarioId() async =>
      int.parse((await _storage.read(key: 'usuarioId'))!);

  Future<String> getNombreCompleto() async =>
      (await _storage.read(key: 'nombreCompleto')) ?? '';

  Future<void> setNombreCompleto(String valor) =>
      _storage.write(key: 'nombreCompleto', value: valor);

  Future<String> getTipoConductor() async =>
      (await _storage.read(key: 'tipoConductor')) ?? 'Particular';

  Future<void> setTipoConductor(String valor) =>
      _storage.write(key: 'tipoConductor', value: valor);

  Future<dynamic> put(String path, Map<String, dynamic> data) async {
    final res = await _dio.put('/api$path', data: data);
    return res.data;
  }

  // ─── Registro ────────────────────────────────────────────────────────────

  Future<void> registro({
    required String nombres,
    required String apellidos,
    required String correo,
    required String password,
    String tipoConductor = 'Particular',
  }) async {
    await _dio.post('/api/usuario', data: {
      'nombres': nombres,
      'apellidos': apellidos,
      'correo': correo,
      'password': password,
      'tipoPlan': 'Gratuito',
      'tipoConductor': tipoConductor,
      'estado': 'Activo',
    });
  }

  // ─── Usuario ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getUsuario(int id) async {
    final res = await _dio.get('/api/usuario/$id');
    return res.data as Map<String, dynamic>;
  }

  // ─── Ranking ─────────────────────────────────────────────────────────────

  Future<List<dynamic>> getRanking() async {
    final res = await _dio.get('/api/ranking');
    return res.data as List;
  }

  // ─── Estadísticas de conducción por categoría ─────────────────────────────

  Future<Map<String, dynamic>> getEstadisticasConduccion(int usuarioId) async {
    final res = await _dio.get('/api/evento/usuario/$usuarioId/estadisticas');
    return res.data as Map<String, dynamic>;
  }

  // ─── Puntos ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getPuntos(int usuarioId) async {
    try {
      final res = await _dio.get('/api/puntosusuario/usuario/$usuarioId');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  // ─── Viaje ───────────────────────────────────────────────────────────────

  Future<List<dynamic>> getViajesUsuario(int usuarioId) async {
    final res = await _dio.get('/api/viaje/usuario/$usuarioId');
    return res.data as List;
  }

  Future<int> iniciarViaje(int usuarioId, int vehiculoId) async {
    final res = await _dio.post('/api/viaje', data: {
      'usuarioId': usuarioId,
      'vehiculoId': vehiculoId,
    });
    return res.data['id'] as int;
  }

  Future<String> finalizarViaje(
    int viajeId, {
    required int duracionMinutos,
    double distanciaKm = 0,
  }) async {
    final res = await _dio.patch('/api/viaje/$viajeId/finalizar', data: {
      // Distancia real calculada con haversine sobre los waypoints GPS del viaje
      // (ver distanciaKmDeRecorrido); redondeada a 2 decimales.
      'distanciaKm': double.parse(distanciaKm.toStringAsFixed(2)),
      'duracionMinutos': duracionMinutos,
      'puntajeConduccion': 100,
    });
    return res.data['mensaje'] as String;
  }

  // ─── Viaje activo (persiste entre sesiones de la pantalla de cámara) ─────

  Future<int?> getViajeActualId() async {
    final stored = await _storage.read(key: 'viajeActualId');
    return stored != null ? int.parse(stored) : null;
  }

  Future<void> clearViajeActual() async {
    await _storage.delete(key: 'viajeActualId');
    await _storage.delete(key: 'viajeActualFecha');
  }

  /// Fecha de hoy en hora de Perú (UTC-5) como 'YYYY-MM-DD'. Se usa para decidir si
  /// el viaje cacheado es del día actual (se continúa) o de un día anterior (se pide
  /// uno nuevo al backend, que cierra el viejo). Igual criterio que el backend.
  String _fechaPeruHoy() {
    final p = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    return '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
  }

  // ─── Recorrido GPS (almacenado en dispositivo, no en servidor) ────────────

  /// Guarda los waypoints GPS del viaje como "lat,lon,speed;lat,lon,speed;..."
  Future<void> guardarRecorrido(int viajeId, List<List<double>> coords) async {
    if (coords.isEmpty) return;
    final valor = coords.map((c) => c.join(',')).join(';');
    await _storage.write(key: 'recorrido_$viajeId', value: valor);
  }

  /// Lee los waypoints del viaje → [lat, lon, speed_kmh]. Lista vacía si no hay datos.
  /// Compatible con datos viejos (solo lat,lon) — speed queda en 0.
  Future<List<List<double>>> getRecorrido(int viajeId) async {
    final stored = await _storage.read(key: 'recorrido_$viajeId');
    if (stored == null || stored.isEmpty) return [];
    return stored.split(';').map((s) {
      final p = s.split(',');
      return [
        double.parse(p[0]),
        double.parse(p[1]),
        p.length > 2 ? double.parse(p[2]) : 0.0,
      ];
    }).toList();
  }

  Future<int> getOrCreateViajeActual(int usuarioId, int vehiculoId) async {
    final hoy = _fechaPeruHoy();
    final existing = await getViajeActualId();
    final fechaGuardada = await _storage.read(key: 'viajeActualFecha');

    // Continuar el viaje cacheado solo si es de HOY (hora Perú): así se puede pausar
    // y seguir el mismo viaje durante el día, incluso sin señal.
    if (existing != null && fechaGuardada == hoy) return existing;

    // Día nuevo (o sin cache válido): el backend retoma el viaje de hoy si existe, o
    // crea uno nuevo cerrando los de días anteriores. Requiere conexión.
    final id = await iniciarViaje(usuarioId, vehiculoId);
    await _storage.write(key: 'viajeActualId', value: id.toString());
    await _storage.write(key: 'viajeActualFecha', value: hoy);
    return id;
  }

  Future<void> cancelarViaje(int viajeId) async {
    await _dio.patch('/api/viaje/$viajeId/cancelar');
    await clearViajeActual();
  }

  // ─── Vehículo / Cámara ───────────────────────────────────────────────────

  Future<(int vehiculoId, int camaraId)> getOrCreateVehiculoCamara() async {
    final vId = await _storage.read(key: 'vehiculoId');
    final cId = await _storage.read(key: 'camaraId');
    if (vId != null && cId != null) {
      return (int.parse(vId), int.parse(cId));
    }
    final uid = await getUsuarioId();
    final placa = 'T${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final vehiculoId = await _registrarVehiculo(uid, placa);
    final camaraId = await _registrarCamara(vehiculoId);
    await _storage.write(key: 'vehiculoId', value: vehiculoId.toString());
    await _storage.write(key: 'camaraId', value: camaraId.toString());
    return (vehiculoId, camaraId);
  }

  Future<int> _registrarVehiculo(int usuarioId, String placa) async {
    final res = await _dio.post('/api/vehiculo', data: {
      'usuarioId': usuarioId,
      'placa': placa,
      'tipoVehiculo': 'Auto',
      'estado': 'Activo',
    });
    return res.data['id'] as int;
  }

  Future<int> _registrarCamara(int vehiculoId) async {
    final res = await _dio.post('/api/camara', data: {
      'vehiculoId': vehiculoId,
      'posicion': 'Frontal',
      'estado': 'Desconectada',
    });
    return res.data['id'] as int;
  }

  // ─── Eventos ─────────────────────────────────────────────────────────────

  /// Registra un evento de conducción. **Offline-first:** lo guarda PRIMERO en
  /// la bandeja local (sobrevive sin señal) y recién intenta enviarlo. Si no hay
  /// conexión, el evento queda pendiente y NO se lanza error — lo reenviará el
  /// sincronizador (Fase B). Nunca lanza: un 4xx definitivo se descarta en
  /// silencio (ver `_intentarEnviar`), el detector no debe romperse por esto.
  Future<void> registrarEvento(
    int viajeId,
    int camaraId,
    String tipoEvento, {
    double? latitud,
    double? longitud,
  }) async {
    final pendiente = EventoPendiente(
      idLocal: const Uuid().v4(),
      viajeId: viajeId,
      camaraId: camaraId,
      tipoEvento: tipoEvento,
      latitud: latitud,
      longitud: longitud,
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );
    await _outbox.insertar(pendiente);
    await _intentarEnviar(pendiente);
  }

  /// Reintenta enviar todos los eventos pendientes en orden de detección (FIFO).
  /// Se detiene en cuanto detecta que no hay conexión (no insiste en vano).
  /// Devuelve cuántos quedan sin enviar (0 = todo sincronizado).
  Future<int> sincronizarPendientes() async {
    for (final e in await _outbox.pendientes()) {
      final r = await _intentarEnviar(e);
      if (r == _ResultadoEnvio.sinRed) break; // sin señal: no seguir intentando
    }
    return _outbox.contarPendientes();
  }

  /// Cantidad de eventos aún sin sincronizar (para diagnóstico / UI).
  Future<int> eventosPendientes() => _outbox.contarPendientes();

  /// Códigos 4xx que NO son culpa del evento, sino transitorios: token vencido
  /// (401/403), timeout (408) o rate limit (429). Hay que mantener el evento
  /// pendiente y reintentar (p. ej. tras renovar el token), nunca descartarlo
  /// — perderíamos datos reales de un viaje sin señal.
  static const _reintentables = {401, 403, 408, 429};

  /// Intenta enviar un evento ya persistido en la bandeja local.
  /// - Éxito → lo borra de la cola (`enviado`).
  /// - Sin señal / servidor 5xx / 4xx transitorio (token, timeout, rate
  ///   limit) → lo deja pendiente (`sinRed`) para reintentar.
  /// - 4xx definitivo (el evento en sí está mal: 400/404/409/422) → lo
  ///   descarta, un reintento no ayudaría (`descartado`).
  Future<_ResultadoEnvio> _intentarEnviar(EventoPendiente e) async {
    try {
      await _dio.post('/api/evento', data: {
        'idLocal': e.idLocal,
        'viajeId': e.viajeId,
        'camaraId': e.camaraId,
        'tipoEvento': e.tipoEvento,
        // Hora real de detección (ISO-8601 UTC): el backend la usa como fecha del
        // evento y para la defensa anti-flood, así la cola offline conserva el orden.
        'fechaDeteccion': e.timestamp,
        'latitud': ?e.latitud,
        'longitud': ?e.longitud,
      });
      await _outbox.marcarEnviado(e.idLocal);
      return _ResultadoEnvio.enviado;
    } on DioException catch (ex) {
      final status = ex.response?.statusCode;
      final reintentar = ex.response == null ||
          (status != null && (status >= 500 || _reintentables.contains(status))) ||
          ex.type == DioExceptionType.connectionError ||
          ex.type == DioExceptionType.connectionTimeout ||
          ex.type == DioExceptionType.sendTimeout ||
          ex.type == DioExceptionType.receiveTimeout;
      if (reintentar) return _ResultadoEnvio.sinRed;
      await _outbox.marcarEnviado(e.idLocal);
      return _ResultadoEnvio.descartado;
    }
  }

  Future<List<dynamic>> getEventosViaje(int viajeId) async {
    final res = await _dio.get('/api/evento/viaje/$viajeId');
    return res.data as List;
  }

  // ─── Premios ─────────────────────────────────────────────────────────────

  Future<List<dynamic>> getPremiosDisponibles() async {
    final res = await _dio.get('/api/premio/disponibles');
    return res.data as List;
  }

  // ─── Canjes ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> canjear(int usuarioId, int premioId) async {
    final res = await _dio.post('/api/canje', data: {
      'usuarioId': usuarioId,
      'premioId': premioId,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCanjeById(int id) async {
    final res = await _dio.get('/api/canje/$id');
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getCanjesByUsuario(int usuarioId) async {
    final res = await _dio.get('/api/canje/usuario/$usuarioId');
    return res.data as List;
  }

  Future<String> anularCanje(int canjeId) async {
    final res = await _dio.patch('/api/canje/$canjeId/anular');
    return res.data['mensaje'] as String;
  }
}

/// Resultado de intentar enviar un evento de la bandeja local al backend.
enum _ResultadoEnvio { enviado, sinRed, descartado }

// ─── Helper global ───────────────────────────────────────────────────────────

String mensajeError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['mensaje'] != null) return data['mensaje'].toString();
    if (e.response?.statusCode == 401) return 'No autorizado. Vuelve a iniciar sesión.';
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'No se pudo conectar al backend. ¿Está en el mismo WiFi?';
    }
    return 'Error ${e.response?.statusCode ?? ''}: ${e.message}';
  }
  return e.toString();
}
