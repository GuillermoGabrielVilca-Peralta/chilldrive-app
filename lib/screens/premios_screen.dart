import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../api_service.dart';
import 'canje_screen.dart';

class PremiosScreen extends StatefulWidget {
  final bool standalone;
  const PremiosScreen({super.key, this.standalone = false});

  @override
  State<PremiosScreen> createState() => _PremiosScreenState();
}

class _PremiosScreenState extends State<PremiosScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late final TabController _tabs;

  // Tab 0 — Disponibles
  List<dynamic> _premios = [];
  int _puntosActuales = 0;

  // Tab 1 — Mis canjes
  List<dynamic> _canjes = [];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await _api.getUsuarioId();
      final results = await Future.wait([
        _api.getPremiosDisponibles(),
        _api.getPuntos(uid),
        _api.getCanjesByUsuario(uid),
      ]);
      if (mounted) {
        final puntos = results[1] as Map<String, dynamic>?;
        setState(() {
          _premios       = results[0] as List;
          _puntosActuales = puntos?['puntosActuales'] as int? ?? 0;
          _canjes        = (results[2] as List).reversed.toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, List<dynamic>> get _porAliado {
    final map = <String, List<dynamic>>{};
    for (final p in _premios) {
      final aliado = p['nombreAliado'] as String? ?? 'Sin aliado';
      map.putIfAbsent(aliado, () => []).add(p);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final tabBar = TabBar(
      controller: _tabs,
      tabs: const [
        Tab(text: 'Disponibles'),
        Tab(text: 'Mis canjes'),
      ],
    );

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _centrado(Icons.error_outline, _error!, _cargar);
    } else {
      body = TabBarView(
        controller: _tabs,
        children: [
          _tabDisponibles(cs),
          _tabCanjes(cs),
        ],
      );
    }

    if (widget.standalone) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Premios'),
          bottom: tabBar,
        ),
        backgroundColor: cs.surfaceContainerLowest,
        body: body,
      );
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Premios',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
            ),
            tabBar,
            Expanded(child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _centrado(Icons.error_outline, _error!, _cargar)
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _tabDisponibles(cs),
                          _tabCanjes(cs),
                        ],
                      )),
          ],
        ),
      ),
    );
  }

  // ── Tab 0: Premios disponibles ──────────────────────────────────────────

  Widget _tabDisponibles(ColorScheme cs) {
    if (_premios.isEmpty) {
      return _centrado(Icons.card_giftcard_outlined,
          'No hay premios disponibles por ahora.', _cargar);
    }
    final grupos = _porAliado;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // Badge puntos
          Container(
            margin: const EdgeInsets.symmetric(vertical: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.monetization_on, color: Color(0xFFD97706)),
                const SizedBox(width: 10),
                Text(
                  'Tus puntos: $_puntosActuales',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E),
                      fontSize: 15),
                ),
              ],
            ),
          ),
          for (final entry in grupos.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 10),
              child: Text(entry.key,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            for (final p in entry.value) _tarjetaPremio(p, cs),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaPremio(Map<String, dynamic> p, ColorScheme cs) {
    final costo = p['puntosRequeridos'] as int? ?? 0;
    final puedesCanjear = _puntosActuales >= costo;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.card_giftcard, color: cs.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['nombre'] as String? ?? '—',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                if ((p['descripcion'] as String?) != null)
                  Text(p['descripcion'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text('$costo pts',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: puedesCanjear
                            ? cs.primary
                            : cs.onSurfaceVariant,
                        fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: puedesCanjear
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CanjeScreen(
                          premio: p,
                          puntosActuales: _puntosActuales,
                        ),
                      ),
                    ).then((canjeado) {
                      if (canjeado == true) _cargar();
                    })
                : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('Canjear'),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Mis canjes ───────────────────────────────────────────────────

  Widget _tabCanjes(ColorScheme cs) {
    if (_canjes.isEmpty) {
      return _centrado(Icons.receipt_long_outlined,
          'Aún no has canjeado ningún premio.', _cargar);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _canjes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _tarjetaCanje(_canjes[i] as Map<String, dynamic>, cs),
      ),
    );
  }

  Widget _tarjetaCanje(Map<String, dynamic> c, ColorScheme cs) {
    final estado   = c['estado'] as String? ?? '—';
    final premio   = c['nombrePremio'] as String? ?? '—';
    final aliado   = c['nombreAliado'] as String? ?? '';
    final pts      = c['puntosUtilizados'] as int? ?? 0;
    final fechaStr = c['fechaCanje'] as String?;
    final fecha    = fechaStr != null ? _fmtFecha(fechaStr) : '—';

    final colores = _coloresEstadoCanje(estado, cs);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _verDetalleCanje(c, cs),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colores.$2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconEstadoCanje(estado),
                  color: colores.$1, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(premio,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(aliado,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(fecha,
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('−$pts pts',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: cs.onSurface)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colores.$2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(estado,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: colores.$1)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _verDetalleCanje(Map<String, dynamic> c, ColorScheme cs) {
    final estado = c['estado'] as String? ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _DetalleCanje(
        canje: c,
        onAnular: estado == 'Activo'
            ? () async {
                try {
                  await _api.anularCanje(c['id'] as int);
                  if (mounted) {
                    Navigator.pop(context);
                    _cargar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Canje anulado. Puntos devueltos.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(mensajeError(e))),
                    );
                  }
                }
              }
            : null,
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  (Color, Color) _coloresEstadoCanje(String estado, ColorScheme cs) =>
      switch (estado) {
        'Usado'   => (Colors.grey.shade600, Colors.grey.shade100),
        'Anulado' => (Colors.red.shade700, Colors.red.shade50),
        _         => (cs.primary, cs.primaryContainer),
      };

  IconData _iconEstadoCanje(String estado) => switch (estado) {
        'Usado'   => Icons.check_circle,
        'Anulado' => Icons.cancel,
        _         => Icons.qr_code,
      };

  String _fmtFecha(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  Widget _centrado(IconData icon, String msg, VoidCallback retry) =>
      Center(
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
              TextButton(onPressed: retry, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
}

// ── Bottom sheet de detalle de canje ────────────────────────────────────────

class _DetalleCanje extends StatelessWidget {
  final Map<String, dynamic> canje;
  final Future<void> Function()? onAnular;

  const _DetalleCanje({required this.canje, required this.onAnular});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final qr     = canje['codigoQr'] as String? ?? '';
    final estado = canje['estado'] as String? ?? '';
    final premio = canje['nombrePremio'] as String? ?? '—';
    final aliado = canje['nombreAliado'] as String? ?? '—';
    final pts    = canje['puntosUtilizados'] as int? ?? 0;

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            Text(premio,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(aliado,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 20),

            // QR (solo si está activo)
            if (estado == 'Activo') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: QrImageView(
                  data: qr.isEmpty ? 'CHILLDRIVE-${canje['id']}' : qr,
                  version: QrVersions.auto,
                  size: 200,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
              const SizedBox(height: 12),
              Text('Muestra este QR en el establecimiento',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      estado == 'Usado' ? Icons.check_circle : Icons.cancel,
                      size: 48,
                      color: estado == 'Usado'
                          ? Colors.green
                          : Colors.red.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      estado == 'Usado'
                          ? 'Este canje ya fue utilizado'
                          : 'Este canje fue anulado',
                      style: TextStyle(
                          fontSize: 14, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Resumen
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                children: [
                  _fila('Puntos utilizados', '$pts pts', cs),
                  const SizedBox(height: 8),
                  _fila('Estado', estado, cs),
                ],
              ),
            ),

            // Botón anular (solo activo)
            if (onAnular != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirmar = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Anular canje'),
                        content: const Text(
                            '¿Anular este canje? Se te devolverán los puntos.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('No')),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Sí, anular',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirmar == true) await onAnular!();
                  },
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  label: const Text('Anular canje',
                      style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fila(String label, String valor, ColorScheme cs) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          Text(valor,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      );
}
