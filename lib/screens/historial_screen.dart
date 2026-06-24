import 'package:flutter/material.dart';
import '../api_service.dart';
import 'detalle_viaje_screen.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final _api = ApiService();
  List<dynamic> _viajes = [];
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
      final uid = await _api.getUsuarioId();
      final data = await _api.getViajesUsuario(uid);
      if (mounted) {
        // Más recientes primero
        setState(() => _viajes = data.reversed.toList());
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
      appBar: AppBar(title: const Text('Historial de viajes')),
      backgroundColor: cs.surfaceContainerLowest,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _centrado(Icons.error_outline, _error!)
              : _viajes.isEmpty
                  ? _centrado(Icons.directions_car_outlined,
                      'Aún no tienes viajes registrados.')
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        itemCount: _viajes.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) =>
                            _tarjetaViaje(_viajes[i] as Map<String, dynamic>, cs),
                      ),
                    ),
    );
  }

  Widget _tarjetaViaje(Map<String, dynamic> v, ColorScheme cs) {
    final estado = v['estado'] as String? ?? '—';
    final pts = v['puntosGanados'] as int? ?? 0;
    final fechaStr = v['fechaInicio'] as String?;
    final fecha = fechaStr != null ? _fmtFecha(fechaStr) : '—';
    final durMin = v['duracionMinutos'] as int?;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DetalleViajeScreen(viajeId: v['id'] as int),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _colorEstado(estado, cs),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconEstado(estado),
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Viaje #${v['id']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '$fecha${durMin != null ? ' · $durMin min' : ''}',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  pts > 0 ? '+$pts pts' : '$pts pts',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: pts > 0 ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                _chipEstado(estado, cs),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _colorEstado(String e, ColorScheme cs) {
    switch (e) {
      case 'Finalizado': return cs.primary;
      case 'Cancelado': return Colors.red.shade400;
      default: return Colors.orange.shade400;
    }
  }

  IconData _iconEstado(String e) {
    switch (e) {
      case 'Finalizado': return Icons.check;
      case 'Cancelado': return Icons.close;
      default: return Icons.play_arrow;
    }
  }

  Widget _chipEstado(String e, ColorScheme cs) {
    Color bg;
    Color fg;
    switch (e) {
      case 'Finalizado':
        bg = cs.primaryContainer; fg = cs.onPrimaryContainer;
      case 'Cancelado':
        bg = Colors.red.shade100; fg = Colors.red.shade800;
      default:
        bg = Colors.orange.shade100; fg = Colors.orange.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(e, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
    );
  }

  String _fmtFecha(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return iso;
    }
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
              const SizedBox(height: 16),
              TextButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
}
