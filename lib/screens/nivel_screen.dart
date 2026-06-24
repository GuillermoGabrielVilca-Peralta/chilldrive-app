import 'package:flutter/material.dart';
import '../api_service.dart';

class NivelScreen extends StatefulWidget {
  const NivelScreen({super.key});

  @override
  State<NivelScreen> createState() => _NivelScreenState();
}

class _NivelScreenState extends State<NivelScreen> {
  final _api = ApiService();

  bool _loading = true;
  int _puntosActuales = 0;
  int _puntosHistoricos = 0;
  String _nivel = 'Bronce';

  // Niveles definidos igual que NivelPuntos.cs en el backend
  static const _niveles = [
    (nombre: 'Bronce',   minimo: 0,    maximo: 299,   color: Color(0xFF92400E), fondo: Color(0xFFFEF3C7), icono: Icons.shield),
    (nombre: 'Plata',    minimo: 300,  maximo: 799,   color: Color(0xFF64748B), fondo: Color(0xFFF1F5F9), icono: Icons.shield),
    (nombre: 'Oro',      minimo: 800,  maximo: 1999,  color: Color(0xFFD97706), fondo: Color(0xFFFEF3C7), icono: Icons.workspace_premium),
    (nombre: 'Platino',  minimo: 2000, maximo: 4999,  color: Color(0xFF6366F1), fondo: Color(0xFFEEF2FF), icono: Icons.military_tech),
    (nombre: 'Diamante', minimo: 5000, maximo: 999999, color: Color(0xFF0EA5E9), fondo: Color(0xFFE0F2FE), icono: Icons.diamond),
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final uid   = await _api.getUsuarioId();
      final datos = await _api.getPuntos(uid);
      if (mounted && datos != null) {
        setState(() {
          _puntosActuales   = datos['puntosActuales']   as int? ?? 0;
          _puntosHistoricos = datos['puntosHistoricos'] as int? ?? 0;
          _nivel            = datos['nivel']             as String? ?? 'Bronce';
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _indiceActual =>
      _niveles.indexWhere((n) => n.nombre == _nivel).clamp(0, _niveles.length - 1);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = _indiceActual;
    final nivelActual = _niveles[idx];

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Mis niveles'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  // ── Nivel actual ────────────────────────────────────
                  Container(
                    margin: const EdgeInsets.only(bottom: 28),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: nivelActual.fondo,
                      borderRadius: BorderRadius.circular(24),
                      border:
                          Border.all(color: nivelActual.color.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        Icon(nivelActual.icono,
                            size: 48, color: nivelActual.color),
                        const SizedBox(height: 8),
                        Text(
                          nivelActual.nombre,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: nivelActual.color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_puntosActuales pts disponibles',
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                        Text(
                          '$_puntosHistoricos pts históricos acumulados',
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                        if (idx < _niveles.length - 1) ...[
                          const SizedBox(height: 16),
                          // Progreso al siguiente nivel
                          _barraProgreso(idx, cs),
                        ] else ...[
                          const SizedBox(height: 12),
                          const Text('¡Has alcanzado el nivel máximo!',
                              style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF0EA5E9))),
                        ],
                      ],
                    ),
                  ),

                  // ── Lista de todos los niveles ───────────────────────
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text('Todos los niveles',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),

                  ..._niveles.asMap().entries.map((e) {
                    final i = e.key;
                    final n = e.value;
                    final desbloqueado = _puntosHistoricos >= n.minimo;
                    final esCurrent   = i == idx;
                    return _nivelCard(n, desbloqueado, esCurrent, cs);
                  }),
                ],
              ),
            ),
    );
  }

  Widget _barraProgreso(int idx, ColorScheme cs) {
    final actual   = _niveles[idx];
    final siguiente = _niveles[idx + 1];
    final rango    = siguiente.minimo - actual.minimo;
    final avance   = (_puntosHistoricos - actual.minimo).clamp(0, rango);
    final fraccion = rango > 0 ? avance / rango : 1.0;
    final faltan   = siguiente.minimo - _puntosHistoricos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Hacia ${siguiente.nombre}',
                style: const TextStyle(fontSize: 12)),
            Text(
              faltan > 0 ? 'Faltan $faltan pts' : '¡Listo!',
              style: TextStyle(fontSize: 12, color: actual.color),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraccion.clamp(0.0, 1.0),
            minHeight: 9,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(actual.color),
          ),
        ),
      ],
    );
  }

  Widget _nivelCard(
    ({String nombre, int minimo, int maximo, Color color, Color fondo, IconData icono}) n,
    bool desbloqueado,
    bool esCurrent,
    ColorScheme cs,
  ) {
    final rangoTexto = n.maximo >= 999999
        ? '${n.minimo}+ pts'
        : '${n.minimo} – ${n.maximo} pts';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: esCurrent ? n.fondo : cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: esCurrent
              ? n.color.withValues(alpha: 0.6)
              : cs.outlineVariant,
          width: esCurrent ? 1.5 : 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: desbloqueado ? n.fondo : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              desbloqueado ? n.icono : Icons.lock_outline,
              size: 24,
              color: desbloqueado ? n.color : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(n.nombre,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: desbloqueado ? n.color : cs.onSurfaceVariant,
                        )),
                    if (esCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: n.color,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Actual',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(rangoTexto,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(
            desbloqueado ? Icons.check_circle : Icons.radio_button_unchecked,
            color:
                desbloqueado ? n.color : cs.onSurfaceVariant.withValues(alpha: 0.4),
            size: 22,
          ),
        ],
      ),
    );
  }
}
