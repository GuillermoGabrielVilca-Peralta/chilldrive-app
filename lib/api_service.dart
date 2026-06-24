import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'config/app_config.dart';

class ApiService {
  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

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
    ));
  }

  // ─── Sesión ──────────────────────────────────────────────────────────────

  Future<void> login(String correo, String password) async {
    final res = await _dio.post('/api/auth/login', data: {
      'correo': correo,
      'password': password,
    });
    final data = res.data as Map<String, dynamic>;
    await _storage.write(key: 'token', value: data['token'] as String);
    await _storage.write(key: 'usuarioId', value: data['usuarioId'].toString());
    await _storage.write(key: 'nombreCompleto', value: data['nombreCompleto'] as String? ?? '');
    await _storage.write(key: 'tipoConductor', value: data['tipoConductor'] as String? ?? 'Particular');
  }

  Future<void> logout() async => _storage.deleteAll();

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

  Future<String> finalizarViaje(int viajeId, {required int duracionMinutos}) async {
    final res = await _dio.patch('/api/viaje/$viajeId/finalizar', data: {
      'distanciaKm': 0,
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

  Future<void> clearViajeActual() => _storage.delete(key: 'viajeActualId');

  Future<int> getOrCreateViajeActual(int usuarioId, int vehiculoId) async {
    final existing = await getViajeActualId();
    if (existing != null) return existing;
    final id = await iniciarViaje(usuarioId, vehiculoId);
    await _storage.write(key: 'viajeActualId', value: id.toString());
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

  Future<void> registrarEvento(
    int viajeId,
    int camaraId,
    String tipoEvento, {
    double? latitud,
    double? longitud,
  }) async {
    await _dio.post('/api/evento', data: {
      'viajeId': viajeId,
      'camaraId': camaraId,
      'tipoEvento': tipoEvento,
      'latitud': ?latitud,
      'longitud': ?longitud,
    });
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
