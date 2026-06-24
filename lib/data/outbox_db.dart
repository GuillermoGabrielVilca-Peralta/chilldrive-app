import 'package:sqflite/sqflite.dart';

/// Un evento de conducción a la espera de ser enviado al backend.
///
/// Se persiste localmente PRIMERO (antes de intentar el envío), de modo que
/// ningún evento se pierda aunque no haya señal en toda la ruta. El `idLocal`
/// es un UUID generado en el cliente: viaja al backend para que un reintento
/// no cree el mismo evento dos veces (idempotencia — Fase C).
class EventoPendiente {
  EventoPendiente({
    required this.idLocal,
    required this.viajeId,
    required this.camaraId,
    required this.tipoEvento,
    required this.timestamp,
    this.latitud,
    this.longitud,
  });

  final String idLocal;
  final int viajeId;
  final int camaraId;
  final String tipoEvento;
  final String timestamp; // ISO-8601 UTC del momento de detección
  final double? latitud;
  final double? longitud;

  Map<String, Object?> toMap() => {
        'id_local': idLocal,
        'viaje_id': viajeId,
        'camara_id': camaraId,
        'tipo_evento': tipoEvento,
        'latitud': latitud,
        'longitud': longitud,
        'timestamp': timestamp,
        'estado': 'pendiente',
      };

  factory EventoPendiente.fromMap(Map<String, Object?> m) => EventoPendiente(
        idLocal: m['id_local'] as String,
        viajeId: m['viaje_id'] as int,
        camaraId: m['camara_id'] as int,
        tipoEvento: m['tipo_evento'] as String,
        latitud: m['latitud'] as double?,
        longitud: m['longitud'] as double?,
        timestamp: m['timestamp'] as String,
      );
}

/// Acceso a la base de datos local SQLite que actúa como bandeja de salida
/// (*outbox*) de eventos. Es SOLO acceso a datos: no contiene lógica de envío
/// ni de negocio — eso vive en `ApiService` (Fase A) y el sincronizador (Fase B).
class OutboxDb {
  OutboxDb._();
  static final OutboxDb instance = OutboxDb._();

  static const _tabla = 'eventos_pendientes';
  Database? _db;

  Future<Database> get _database async => _db ??= await _abrir();

  Future<Database> _abrir() async {
    final ruta = '${await getDatabasesPath()}/chilldrive_outbox.db';
    return openDatabase(
      ruta,
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE $_tabla (
          id_local    TEXT PRIMARY KEY,
          viaje_id    INTEGER NOT NULL,
          camara_id   INTEGER NOT NULL,
          tipo_evento TEXT    NOT NULL,
          latitud     REAL,
          longitud    REAL,
          timestamp   TEXT    NOT NULL,
          estado      TEXT    NOT NULL DEFAULT 'pendiente'
        )
      '''),
    );
  }

  /// Guarda un evento como pendiente. Idempotente por `id_local`.
  Future<void> insertar(EventoPendiente e) async {
    final db = await _database;
    await db.insert(
      _tabla,
      e.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Eventos aún no confirmados por el backend, en orden de detección (FIFO).
  Future<List<EventoPendiente>> pendientes() async {
    final db = await _database;
    final filas = await db.query(_tabla, orderBy: 'timestamp ASC');
    return filas.map(EventoPendiente.fromMap).toList();
  }

  /// Marca un evento como confirmado por el backend → lo elimina de la cola.
  Future<void> marcarEnviado(String idLocal) async {
    final db = await _database;
    await db.delete(_tabla, where: 'id_local = ?', whereArgs: [idLocal]);
  }

  /// Cuántos eventos quedan por sincronizar (para UI / diagnóstico).
  Future<int> contarPendientes() async {
    final db = await _database;
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM $_tabla');
    return Sqflite.firstIntValue(r) ?? 0;
  }
}
