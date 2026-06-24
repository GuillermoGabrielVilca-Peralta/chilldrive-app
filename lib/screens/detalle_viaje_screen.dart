import 'package:flutter/material.dart';
import '../api_service.dart';

class DetalleViajeScreen extends StatefulWidget {
  final int viajeId;
  const DetalleViajeScreen({super.key, required this.viajeId});

  @override
  State<DetalleViajeScreen> createState() => _DetalleViajeScreenState();
}

class _DetalleViajeScreenState extends State<DetalleViajeScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _viaje;
  List<dynamic> _eventos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Obtenemos el viaje desde la lista del usuario (GET /viaje/{id} no existe sin verificación)
      // y los eventos del viaje en paralelo.
      final uid = await _api.getUsuarioId();
      final results = await Future.wait([
        _api.getViajesUsuario(uid),
        _api.getEventosViaje(widget.viajeId),
      ]);
      final viajes = results[0];
      final eventos = results[1];
      final viaje = viajes.firstWhere(
        (v) => v['id'] == widget.viajeId,
        orElse: () => null,
      );
      if (mounted) {
        setState(() {
          _viaje = viaje as Map<String, dynamic>?;
          _eventos = eventos;
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
      appBar: AppBar(title: Text('Viaje #${widget.viajeId}')),
      backgroundColor: cs.surfaceContainerLowest,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _centrado(Icons.error_outline, _error!)
              : RefreshIndicator(
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
                        ..._eventos.map((e) =>
                            _tarjetaEvento(e as Map<String, dynamic>, cs)),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _cabecera(ColorScheme cs) {
    final v = _viaje!;
    final estado = v['estado'] as String? ?? '—';
    // Para viajes finalizados se usa puntosGanados del backend;
    // para En Curso se suma el impacto de los eventos ya registrados.
    final ptsGuardados = v['puntosGanados'] as int? ?? 0;
    final pts = estado == 'Finalizado'
        ? ptsGuardados
        : _eventos.fold<int>(
            0, (s, e) => s + ((e['impactoPuntaje'] as int?) ?? 0));
    final durMin = v['duracionMinutos'] as int?;
    final puntaje = v['puntajeConduccion'];

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
                'Eventos',
                '${_eventos.length}',
                cs.onSurface,
              ),
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
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );

  Widget _tarjetaEvento(Map<String, dynamic> e, ColorScheme cs) {
    final tipo = e['tipoEvento'] as String? ?? '—';
    final impacto = e['impactoPuntaje'] as int? ?? 0;
    final fecha = e['fechaEvento'] as String?;

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

  Color _colorImpacto(int pts) {
    if (pts > 0) return Colors.green.shade500;
    if (pts < 0) return Colors.red.shade400;
    return Colors.orange.shade400;
  }

  IconData _iconTipo(String tipo) {
    if (tipo.contains('Respetada')) return Icons.check;
    if (tipo.contains('Ignorada')) return Icons.close;
    if (tipo.contains('Velocidad')) return Icons.speed;
    if (tipo.contains('Peatón')) return Icons.directions_walk;
    if (tipo.contains('Carril')) return Icons.warning;
    if (tipo.contains('Frenado')) return Icons.emergency;
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

  Widget _centrado(IconData icon, String msg) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
}
