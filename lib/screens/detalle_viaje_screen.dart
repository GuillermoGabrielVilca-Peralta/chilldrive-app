import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../api_service.dart';

class DetalleViajeScreen extends StatefulWidget {
  final int viajeId;
  const DetalleViajeScreen({super.key, required this.viajeId});

  @override
  State<DetalleViajeScreen> createState() => _DetalleViajeScreenState();
}

class _DetalleViajeScreenState extends State<DetalleViajeScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();

  Map<String, dynamic>? _viaje;
  List<Map<String, dynamic>> _eventos = [];
  List<List<double>> _recorrido = []; // [lat, lon, speed_kmh]

  bool _loading = true;
  String? _error;

  // Filtro activo en la pestaña del mapa
  String? _filtroTipo;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await _api.getUsuarioId();
      final (viajes, eventos, waypoints) = await (
        _api.getViajesUsuario(uid),
        _api.getEventosViaje(widget.viajeId),
        _api.getRecorrido(widget.viajeId),
      ).wait;

      final viaje = viajes.firstWhere(
        (v) => v['id'] == widget.viajeId,
        orElse: () => null,
      );

      if (mounted) {
        setState(() {
          _viaje     = viaje as Map<String, dynamic>?;
          _eventos   = eventos.cast<Map<String, dynamic>>();
          _recorrido = waypoints;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Viaje #${widget.viajeId}'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'General'),
            Tab(text: 'Calificación'),
            Tab(text: 'Mapa'),
          ],
        ),
      ),
      backgroundColor: cs.surfaceContainerLowest,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _centrado(Icons.error_outline, _error!)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _tabGeneral(cs),
                    _tabCalificacion(cs),
                    _tabMapa(cs),
                  ],
                ),
    );
  }

  // ── Tab 1: General ────────────────────────────────────────────────────────

  Widget _tabGeneral(ColorScheme cs) => RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_viaje != null) _cabecera(cs),
            const SizedBox(height: 20),
            if (_eventos.isEmpty)
              _centrado(Icons.sensors_off,
                  'No hay eventos registrados en este viaje.')
            else ...[
              Text('Eventos (${_eventos.length})',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ..._eventos.map((e) => _tarjetaEvento(e, cs)),
            ],
          ],
        ),
      );

  // ── Tab 2: Calificación ───────────────────────────────────────────────────
  // Score por categoría de ESTE viaje, calculado en el cliente desde los eventos
  // ya cargados (funciona offline). Misma fórmula que el backend usa para el
  // histórico global: score = max(0, 100 + suma de impactos negativos de la
  // categoría). El general es el promedio de las categorías.

  static const _categorias = <({String nombre, String tipo, IconData icon})>[
    (nombre: 'Velocidad',   tipo: 'Exceso Velocidad',   icon: Icons.speed),
    (nombre: 'Frenado',     tipo: 'Frenado Brusco',     icon: Icons.emergency),
    (nombre: 'Aceleración', tipo: 'Aceleración Brusca', icon: Icons.keyboard_double_arrow_up),
    (nombre: 'Giros',       tipo: 'Giro Brusco',        icon: Icons.turn_right),
    (nombre: 'Celular',     tipo: 'Uso Celular',        icon: Icons.smartphone),
  ];

  ({int score, int cantidad}) _calcularCategoria(String tipo) {
    final delTipo = _eventos.where((e) => e['tipoEvento'] == tipo);
    final suma = delTipo.fold<int>(
        0, (s, e) => s + ((e['impactoPuntaje'] as int?) ?? 0));
    final score = (100 + suma).clamp(0, 100).toInt(); // suma es ≤ 0 (infracciones)
    return (score: score, cantidad: delTipo.length);
  }

  Widget _tabCalificacion(ColorScheme cs) {
    final filas = _categorias
        .map((c) => (cat: c, res: _calcularCategoria(c.tipo)))
        .toList();
    final general = filas.isEmpty
        ? 100
        : (filas.fold<int>(0, (s, f) => s + f.res.score) / filas.length).round();
    final totalInfracciones =
        filas.fold<int>(0, (s, f) => s + f.res.cantidad);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        _anilloScore(general, totalInfracciones, cs),
        const SizedBox(height: 24),
        Text('Por categoría',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...filas.map((f) => _filaCategoria(f.cat, f.res, cs)),
        const SizedBox(height: 16),
        Text(
          'Calculado a partir de los ${_eventos.length} eventos de este viaje. '
          '100 = sin infracciones en esa categoría.',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _anilloScore(int score, int infracciones, ColorScheme cs) {
    final color = _colorScore(score);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 10,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$score',
                        style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    Text('/100',
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(_etiquetaScore(score),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(
            infracciones == 0
                ? 'Sin infracciones detectadas'
                : '$infracciones infracción${infracciones == 1 ? '' : 'es'} en total',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _filaCategoria(
      ({String nombre, String tipo, IconData icon}) cat,
      ({int score, int cantidad}) res,
      ColorScheme cs) {
    final color = _colorScore(res.score);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(cat.icon, size: 22, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(cat.nombre,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('${res.score}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: res.score / 100,
                    minHeight: 6,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  res.cantidad == 0
                      ? 'Sin eventos'
                      : '${res.cantidad} evento${res.cantidad == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _colorScore(int score) {
    if (score >= 80) return Colors.green.shade600;
    if (score >= 50) return Colors.orange.shade600;
    return Colors.red.shade500;
  }

  String _etiquetaScore(int score) {
    if (score >= 85) return 'Excelente';
    if (score >= 70) return 'Buena';
    if (score >= 50) return 'Regular';
    return 'Riesgosa';
  }

  // ── Tab 3: Mapa ───────────────────────────────────────────────────────────

  Widget _tabMapa(ColorScheme cs) {
    // Eventos con coordenadas válidas
    final conCoords = _eventos.where((e) {
      final lat = e['latitud'];
      final lon = e['longitud'];
      return lat != null && lon != null;
    }).toList();

    // Aplicar filtro de tipo si hay uno activo
    final filtrados = _filtroTipo == null
        ? conCoords
        : conCoords.where((e) => e['tipoEvento'] == _filtroTipo).toList();

    // Tipos disponibles para el filtro
    final tiposDisponibles = conCoords
        .map((e) => e['tipoEvento'] as String)
        .toSet()
        .toList()
      ..sort();

    // Centro del mapa: primer waypoint, primer evento con coords, o Lima
    LatLng centro = const LatLng(-12.0464, -77.0428);
    if (_recorrido.isNotEmpty) {
      centro = LatLng(_recorrido.first[0], _recorrido.first[1]);
    } else if (conCoords.isNotEmpty) {
      centro = LatLng(
        (conCoords.first['latitud'] as num).toDouble(),
        (conCoords.first['longitud'] as num).toDouble(),
      );
    }

    final sinDatos = _recorrido.isEmpty && conCoords.isEmpty;

    return Column(
      children: [
        // ── Chips de filtro ─────────────────────────────────────────────────
        if (tiposDisponibles.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              scrollDirection: Axis.horizontal,
              children: [
                _chip('Todos', _filtroTipo == null, cs,
                    () => setState(() => _filtroTipo = null)),
                ...tiposDisponibles.map((t) => _chip(t, _filtroTipo == t, cs,
                    () => setState(() => _filtroTipo = t))),
              ],
            ),
          ),

        // ── Leyenda de colores ──────────────────────────────────────────────
        if (_recorrido.length >= 2)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _leyenda(Colors.blue.shade600, 'Suave'),
                const SizedBox(width: 20),
                _leyenda(Colors.orange.shade500, 'Moderado'),
                const SizedBox(width: 20),
                _leyenda(Colors.red.shade500, 'Agresivo'),
              ],
            ),
          ),

        // ── Mapa ────────────────────────────────────────────────────────────
        Expanded(
          child: sinDatos
              ? _centrado(Icons.map_outlined,
                  'No hay datos de ruta para este viaje.\nLos mapas se generan en viajes futuros.')
              : FlutterMap(
                  options: MapOptions(
                    initialCenter: centro,
                    initialZoom: 15,
                  ),
                  children: [
                    // Capa de tiles OSM (gratuita, sin API key)
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.chilldrive_app',
                    ),

                    // Polilínea coloreada por tasa de aceleración
                    if (_recorrido.length >= 2)
                      PolylineLayer(polylines: _segmentosColoreados()),

                    // Marcadores de inicio y fin de ruta
                    if (_recorrido.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          _marcadorRuta(
                              LatLng(_recorrido.first[0], _recorrido.first[1]),
                              Icons.play_arrow, Colors.green),
                          if (_recorrido.length > 1)
                            _marcadorRuta(
                                LatLng(_recorrido.last[0], _recorrido.last[1]),
                                Icons.flag, Colors.red),
                        ],
                      ),

                    // Marcadores de eventos
                    MarkerLayer(
                      markers: filtrados.map((e) {
                        final lat =
                            (e['latitud'] as num).toDouble();
                        final lon =
                            (e['longitud'] as num).toDouble();
                        final tipo = e['tipoEvento'] as String? ?? '';
                        final impacto = e['impactoPuntaje'] as int? ?? 0;
                        return Marker(
                          point: LatLng(lat, lon),
                          width: 36,
                          height: 36,
                          child: Tooltip(
                            message: tipo,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _colorImpacto(impacto),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4)
                                ],
                              ),
                              child: Icon(_iconTipo(tipo),
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Marker _marcadorRuta(LatLng punto, IconData icon, Color color) => Marker(
        point: punto,
        width: 28,
        height: 28,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      );

  Widget _chip(
          String label, bool activo, ColorScheme cs, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: activo ? cs.onPrimary : cs.onSurfaceVariant)),
          selected: activo,
          selectedColor: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          onSelected: (_) => onTap(),
          visualDensity: VisualDensity.compact,
        ),
      );

  // ── Widgets compartidos ───────────────────────────────────────────────────

  Widget _cabecera(ColorScheme cs) {
    final v = _viaje!;
    final estado = v['estado'] as String? ?? '—';
    final ptsGuardados = v['puntosGanados'] as int? ?? 0;
    final pts = estado == 'Finalizado'
        ? ptsGuardados
        : _eventos.fold<int>(
            0, (s, e) => s + ((e['impactoPuntaje'] as int?) ?? 0));
    final durMin = v['duracionMinutos'] as int?;
    final puntaje = v['puntajeConduccion'];
    final distKm = (v['distanciaKm'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_fmtFecha(v['fechaInicio'] as String? ?? ''),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  if (durMin != null)
                    Text('$durMin min',
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurfaceVariant)),
                ],
              ),
              _chipEstado(estado, cs),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metrica('Puntos', pts > 0 ? '+$pts' : '$pts',
                  pts > 0 ? cs.primary : cs.onSurfaceVariant),
              _metrica(
                'Puntaje',
                puntaje != null
                    ? '${(puntaje as num).toStringAsFixed(0)}/100'
                    : '—',
                cs.onSurface,
              ),
              _metrica(
                'Distancia',
                distKm > 0 ? '${distKm.toStringAsFixed(1)} km' : '—',
                cs.onSurface,
              ),
              _metrica('Eventos', '${_eventos.length}', cs.onSurface),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metrica(String label, String valor, Color color) => Column(
        children: [
          Text(valor,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );

  Widget _tarjetaEvento(Map<String, dynamic> e, ColorScheme cs) {
    final tipo    = e['tipoEvento'] as String? ?? '—';
    final impacto = e['impactoPuntaje'] as int? ?? 0;
    final fecha   = e['fechaEvento'] as String?;
    final lat     = e['latitud'];
    final lon     = e['longitud'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _colorImpacto(impacto),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconTipo(tipo), color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tipo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                if (fecha != null)
                  Text(_fmtHora(fecha),
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          // Ícono de pin si tiene coordenadas → tap abre el mapa
          if (lat != null && lon != null)
            IconButton(
              icon: Icon(Icons.location_on,
                  size: 18, color: cs.primary),
              onPressed: () {
                _filtroTipo = tipo;
                _tabController.animateTo(1);
              },
              tooltip: 'Ver en mapa',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          Text(
            impacto > 0 ? '+$impacto pts' : '$impacto pts',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: impacto > 0
                  ? Colors.green.shade700
                  : impacto < 0
                      ? Colors.red.shade700
                      : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Cada segmento se colorea según el cambio de velocidad entre puntos consecutivos:
  /// azul = suave (<10 km/h en 10 s), naranja = moderado (10-20), rojo = agresivo (>20)
  List<Polyline> _segmentosColoreados() {
    final segments = <Polyline>[];
    for (int i = 0; i < _recorrido.length - 1; i++) {
      final w1 = _recorrido[i];
      final w2 = _recorrido[i + 1];
      final v1 = w1.length > 2 ? w1[2] : 0.0;
      final v2 = w2.length > 2 ? w2[2] : 0.0;
      final deltaV = (v2 - v1).abs();

      final color = deltaV >= 20
          ? Colors.red.shade500
          : deltaV >= 10
              ? Colors.orange.shade500
              : Colors.blue.shade600;

      segments.add(Polyline(
        points: [LatLng(w1[0], w1[1]), LatLng(w2[0], w2[1])],
        strokeWidth: 5,
        color: color,
      ));
    }
    return segments;
  }

  Widget _leyenda(Color color, String label) => Row(
        children: [
          Container(
            width: 20, height: 4,
            decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );

  Color _colorImpacto(int pts) {
    if (pts > 0) return Colors.green.shade500;
    if (pts < 0) return Colors.red.shade400;
    return Colors.orange.shade400;
  }

  IconData _iconTipo(String tipo) {
    if (tipo.contains('Respetada'))  return Icons.check;
    if (tipo.contains('Ignorada'))   return Icons.close;
    if (tipo.contains('Velocidad'))  return Icons.speed;
    if (tipo.contains('Peatón'))     return Icons.directions_walk;
    if (tipo.contains('Carril'))     return Icons.warning;
    if (tipo.contains('Frenado'))    return Icons.emergency;
    if (tipo.contains('Aceleración')) return Icons.keyboard_double_arrow_up;
    if (tipo.contains('Giro'))       return Icons.turn_right;
    if (tipo.contains('Celular'))    return Icons.smartphone;
    return Icons.sensors;
  }

  Widget _chipEstado(String e, ColorScheme cs) {
    Color bg, fg;
    switch (e) {
      case 'Finalizado':
        bg = cs.primaryContainer; fg = cs.onPrimaryContainer;
      case 'Cancelado':
        bg = Colors.red.shade100; fg = Colors.red.shade800;
      default:
        bg = Colors.orange.shade100; fg = Colors.orange.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(e,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  String _fmtFecha(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) { return iso; }
  }

  String _fmtHora(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  Widget _centrado(IconData icon, String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
}
