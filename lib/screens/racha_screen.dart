import 'package:flutter/material.dart';
import '../api_service.dart';

class RachaScreen extends StatefulWidget {
  const RachaScreen({super.key});

  @override
  State<RachaScreen> createState() => _RachaScreenState();
}

class _RachaScreenState extends State<RachaScreen> {
  final _api = ApiService();

  bool _loading = true;
  int _rachaActual = 0;

  // Retos de racha: { días, título, descripción, recompensa }
  static const _retos = [
    (dias: 3,  titulo: '3 días en racha',   desc: 'Conduce 3 días seguidos',         recompensa: '+50 puntos extra',       icono: Icons.local_fire_department),
    (dias: 7,  titulo: 'Semana perfecta',   desc: 'Conduce todos los días de la semana', recompensa: 'Premio especial Bronce', icono: Icons.emoji_events),
    (dias: 14, titulo: 'Dos semanas',       desc: '14 días seguidos al volante',     recompensa: 'Premio especial Plata',  icono: Icons.workspace_premium),
    (dias: 30, titulo: 'Mes completo',      desc: '30 días de racha ininterrumpida', recompensa: 'Premio especial Oro',    icono: Icons.military_tech),
    (dias: 90, titulo: 'Conductor élite',   desc: '90 días consecutivos conduciendo', recompensa: 'Premio exclusivo Diamante', icono: Icons.diamond),
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
      final viajes = await _api.getViajesUsuario(uid);

      // Días únicos con viaje finalizado → calcular racha consecutiva
      final dias = <DateTime>{};
      for (final v in viajes) {
        if (v['estado'] != 'Finalizado') continue;
        final fecha = DateTime.tryParse(v['fechaInicio'] as String? ?? '');
        if (fecha != null) {
          dias.add(DateTime(fecha.year, fecha.month, fecha.day));
        }
      }

      final racha = _calcularRacha(dias);
      if (mounted) setState(() => _rachaActual = racha);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _calcularRacha(Set<DateTime> dias) {
    if (dias.isEmpty) return 0;
    final hoy       = DateTime.now();
    final hoyClean  = DateTime(hoy.year, hoy.month, hoy.day);
    int racha       = 0;
    var diaCheck    = hoyClean;

    // Acepta hoy O ayer como punto de partida (no penaliza si aún no condujo hoy)
    if (!dias.contains(diaCheck)) {
      diaCheck = diaCheck.subtract(const Duration(days: 1));
    }

    while (dias.contains(diaCheck)) {
      racha++;
      diaCheck = diaCheck.subtract(const Duration(days: 1));
    }
    return racha;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Mi racha'),
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
                  // ── Encabezado racha actual ─────────────────────────
                  Container(
                    margin: const EdgeInsets.only(bottom: 28),
                    padding: const EdgeInsets.symmetric(
                        vertical: 28, horizontal: 20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFF97316)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.local_fire_department_rounded,
                            size: 52, color: Colors.white),
                        const SizedBox(height: 10),
                        Text(
                          '$_rachaActual',
                          style: const TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1),
                        ),
                        const Text('días de racha',
                            style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70)),
                        const SizedBox(height: 8),
                        Text(
                          _rachaActual == 0
                              ? 'Comienza hoy tu racha 🚗'
                              : _rachaActual == 1
                                  ? '¡Buen comienzo, sigue así!'
                                  : '¡Increíble, no pares!',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),

                  // ── Retos ───────────────────────────────────────────
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text('Retos de racha',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),

                  ..._retos.map((r) => _retoCard(r, cs)),
                ],
              ),
            ),
    );
  }

  Widget _retoCard(
    ({int dias, String titulo, String desc, String recompensa, IconData icono}) r,
    ColorScheme cs,
  ) {
    final alcanzado = _rachaActual >= r.dias;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alcanzado
            ? const Color(0xFFFFF7ED)
            : cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alcanzado
              ? const Color(0xFFF97316)
              : cs.outlineVariant,
          width: alcanzado ? 1.5 : 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: alcanzado
                  ? const Color(0xFFFEE2E2)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(r.icono,
                size: 24,
                color: alcanzado
                    ? const Color(0xFFEF4444)
                    : cs.onSurfaceVariant),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(r.desc,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.card_giftcard_outlined,
                        size: 13, color: Color(0xFFD97706)),
                    const SizedBox(width: 4),
                    Text(r.recompensa,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFD97706),
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Progreso o check
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: alcanzado
                      ? const Color(0xFFEF4444)
                      : cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  alcanzado ? Icons.check : Icons.lock_outline,
                  size: 18,
                  color: alcanzado ? Colors.white : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text('${r.dias}d',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
