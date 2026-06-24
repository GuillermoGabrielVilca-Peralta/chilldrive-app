import 'package:flutter/material.dart';
import '../api_service.dart';
import 'deteccion_screen.dart';
import 'historial_screen.dart';

/// Tab de Viaje: mantiene toda la lógica de iniciar / continuar / cancelar viaje.
class ViajeTab extends StatefulWidget {
  const ViajeTab({super.key});

  @override
  State<ViajeTab> createState() => _ViajeTabState();
}

class _ViajeTabState extends State<ViajeTab> {
  final _api = ApiService();
  String _puntos = '—';
  String _nivel = '—';
  int? _viajeActualId;
  bool _iniciando = false;

  @override
  void initState() {
    super.initState();
    _refrescarEstado();
  }

  Future<void> _refrescarEstado() async {
    await _refrescarPuntos();
    final id = await _api.getViajeActualId();
    if (mounted) setState(() => _viajeActualId = id);
  }

  Future<void> _refrescarPuntos() async {
    try {
      final uid = await _api.getUsuarioId();
      final p = await _api.getPuntos(uid);
      if (mounted) {
        setState(() {
          _puntos = p == null ? '0' : '${p['puntosActuales']}';
          _nivel = p == null ? '—' : '${p['nivel']}';
        });
      }
    } catch (_) {}
  }

  Future<void> _abrirDeteccion() async {
    setState(() => _iniciando = true);
    try {
      final (vehiculoId, camaraId) = await _api.getOrCreateVehiculoCamara();
      final uid = await _api.getUsuarioId();
      final viajeId = await _api.getOrCreateViajeActual(uid, vehiculoId);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            DeteccionScreen(viajeId: viajeId, camaraId: camaraId),
      ));
      await _refrescarEstado();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensajeError(e))));
      }
    } finally {
      if (mounted) setState(() => _iniciando = false);
    }
  }

  Future<void> _cancelarViajeActual() async {
    final id = _viajeActualId;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar viaje'),
        content: Text(
            '¿Cancelar el viaje #$id?\nLos puntos ya obtenidos se conservan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sí, cancelar',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _api.cancelarViaje(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Viaje cancelado.')));
      }
      await _refrescarEstado();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensajeError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tieneViaje = _viajeActualId != null;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refrescarEstado,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 8),
              // ── Encabezado ─────────────────────────────────────────────
              Text('Tu viaje',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
              const SizedBox(height: 4),
              Text(
                tieneViaje
                    ? 'Tienes un viaje en curso'
                    : 'Listo para el camino',
                style:
                    TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),

              // ── Puntos ─────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.monetization_on,
                          color: Color(0xFFD97706), size: 26),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Puntos ChillDrive',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                        Text(_puntos,
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_nivel,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onPrimaryContainer)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Chip de viaje activo ────────────────────────────────────
              if (tieneViaje) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.fiber_manual_record,
                          size: 12, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Viaje #$_viajeActualId en progreso',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: cs.onPrimaryContainer)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Botón principal ─────────────────────────────────────────
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _iniciando ? null : _abrirDeteccion,
                  icon: _iniciando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(tieneViaje
                          ? Icons.videocam
                          : Icons.play_arrow_rounded),
                  label: Text(
                    tieneViaje ? 'Continuar viaje' : 'Iniciar viaje',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),

              // ── Cancelar ───────────────────────────────────────────────
              if (tieneViaje) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _cancelarViajeActual,
                  icon: const Icon(Icons.cancel_outlined,
                      color: Colors.red, size: 18),
                  label: const Text('Cancelar viaje activo',
                      style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              TextButton(
                onPressed: _refrescarEstado,
                child: const Text('Actualizar'),
              ),
              const SizedBox(height: 8),

              // ── Historial de viajes ──────────────────────────────────
              const Divider(height: 32),
              const Text('Historial de viajes',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Revisa todos tus viajes anteriores, eventos\ndetectados y puntos obtenidos.',
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const HistorialScreen()),
                  ),
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Ver tus viajes'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
