import 'package:flutter/material.dart';
import '../api_service.dart';
import 'ranking_screen.dart';
import 'racha_screen.dart';
import 'nivel_screen.dart';
import 'perfil_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onIniciarViaje;
  const DashboardScreen({super.key, required this.onIniciarViaje});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiService();

  bool _loading = true;
  String _nombre = '';
  int _puntosActuales = 0;
  String _nivel = '—';
  int? _rankingPos;
  int _rachaDias = 0;

  // Retos
  int _viajesAnalizados  = 0;
  int _viajesSinFrenazos = 0;
  int _senalesRespetadas = 0;
  int _metaSenales       = 5;
  int _viajesEstaSemana  = 0;
  static const int _metaViajesSemana = 3;

  // Estado previo de retos para detectar recién completados
  bool _primeraCarga         = true;
  bool _prevFrenazosCompleto = false;
  bool _prevSenalesCompleto  = false;
  bool _prevSemanalCompleto  = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final uid    = await _api.getUsuarioId();
      final nombre = await _api.getNombreCompleto();

      final results = await Future.wait([
        _api.getPuntos(uid),
        _api.getRanking(),
        _api.getViajesUsuario(uid),
      ]);

      final puntos  = results[0] as Map<String, dynamic>?;
      final ranking = results[1] as List;
      final viajes  = results[2] as List;

      // ── Ranking ──────────────────────────────────────────────────
      final rankingOrdenado = List.of(ranking)
        ..sort((a, b) =>
            ((b['puntosActuales'] as int?) ?? 0)
                .compareTo((a['puntosActuales'] as int?) ?? 0));
      final pos = rankingOrdenado.indexWhere((r) => r['usuarioId'] == uid);

      // ── Racha y viajes esta semana ────────────────────────────────
      final ahora        = DateTime.now();
      final inicioSemana = DateTime(
          ahora.year, ahora.month, ahora.day - (ahora.weekday - 1));
      final diasSet      = <DateTime>{};
      int semana         = 0;

      for (final v in viajes) {
        if (v['estado'] != 'Finalizado') continue;
        final fechaStr = v['fechaInicio'] as String?;
        final fecha    = fechaStr != null ? DateTime.tryParse(fechaStr) : null;
        if (fecha != null) {
          diasSet.add(DateTime(fecha.year, fecha.month, fecha.day));
          if (!fecha.isBefore(inicioSemana)) semana++;
        }
      }
      final racha = _calcularRacha(diasSet);

      // ── Eventos de los últimos 5 viajes finalizados ───────────────
      final finalizados = viajes
          .where((v) => v['estado'] == 'Finalizado')
          .take(5)
          .toList();

      int sinFrenazos = 0;
      int senalesResp = 0;

      if (finalizados.isNotEmpty) {
        final eventosLista = await Future.wait(
          finalizados.map((v) => _api.getEventosViaje(v['id'] as int)),
        );
        for (final eventos in eventosLista) {
          final hayFrenazo = eventos.any((e) =>
              ((e['tipoEvento'] as String?) ?? '')
                  .toLowerCase()
                  .contains('frenado'));
          if (!hayFrenazo) sinFrenazos++;
          senalesResp += eventos
              .where((e) => ((e['tipoEvento'] as String?) ?? '')
                  .toLowerCase()
                  .contains('respetada'))
              .length;
        }
      }

      if (mounted) {
        setState(() {
          _nombre            = nombre;
          _puntosActuales    = puntos?['puntosActuales'] as int? ?? 0;
          _nivel             = puntos?['nivel'] as String? ?? '—';
          _rankingPos        = pos >= 0 ? pos + 1 : null;
          _rachaDias         = racha;
          _viajesEstaSemana  = semana;
          _viajesAnalizados  = finalizados.length;
          _viajesSinFrenazos = sinFrenazos;
          _senalesRespetadas = senalesResp;
          _metaSenales       = finalizados.length * 2;
        });
        _verificarRetosCompletados(sinFrenazos, finalizados.length, senalesResp,
            finalizados.length * 2, semana);
      }
    } catch (e) {
      debugPrint('[Dashboard] Error al cargar datos: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _verificarRetosCompletados(
    int sinFrenazos, int metaFrenazos,
    int senales, int metaSenales,
    int semana,
  ) {
    final frenazosOk = metaFrenazos > 0 && sinFrenazos >= metaFrenazos;
    final senalesOk  = metaSenales  > 0 && senales     >= metaSenales;
    final semanalOk  = semana       >= _metaViajesSemana;

    if (_primeraCarga) {
      // Primera carga: solo establecemos la línea base, sin celebrar.
      _prevFrenazosCompleto = frenazosOk;
      _prevSenalesCompleto  = senalesOk;
      _prevSemanalCompleto  = semanalOk;
      _primeraCarga = false;
      return;
    }

    final recienCompletados = <_RetoInfo>[];
    if (!_prevFrenazosCompleto && frenazosOk) {
      recienCompletados.add(const _RetoInfo('Cero frenadas bruscas',
          Icons.emergency_outlined, Color(0xFF22C55E)));
    }
    if (!_prevSenalesCompleto && senalesOk) {
      recienCompletados.add(const _RetoInfo('Respetar semáforos',
          Icons.traffic, Color(0xFF3B82F6)));
    }
    if (!_prevSemanalCompleto && semanalOk) {
      recienCompletados.add(const _RetoInfo('Conductor semanal',
          Icons.calendar_today, Color(0xFFD97706)));
    }

    _prevFrenazosCompleto = frenazosOk;
    _prevSenalesCompleto  = senalesOk;
    _prevSemanalCompleto  = semanalOk;

    if (recienCompletados.isNotEmpty) {
      // Pequeño delay para que el build termine antes de mostrar el dialog
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _mostrarCelebracion(recienCompletados);
      });
    }
  }

  void _mostrarCelebracion(List<_RetoInfo> retos) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'cerrar',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (context2, anim, secondAnim, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
        child: FadeTransition(opacity: anim, child: child),
      ),
      pageBuilder: (ctx, anim1, anim2) => _CelebracionDialog(retos: retos),
    );
  }

  int _calcularRacha(Set<DateTime> dias) {
    if (dias.isEmpty) return 0;
    final hoyClean = DateTime.now();
    var diaCheck   = DateTime(hoyClean.year, hoyClean.month, hoyClean.day);
    if (!dias.contains(diaCheck)) {
      diaCheck = diaCheck.subtract(const Duration(days: 1));
    }
    int racha = 0;
    while (dias.contains(diaCheck)) {
      racha++;
      diaCheck = diaCheck.subtract(const Duration(days: 1));
    }
    return racha;
  }

  String get _iniciales {
    final p = _nombre.trim().split(' ');
    if (p.length >= 2) return '${p[0][0]}${p[1][0]}'.toUpperCase();
    return _nombre.isNotEmpty ? _nombre[0].toUpperCase() : '?';
  }

  void _mostrarTooltipPuntos(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TooltipPuntos(
        puntos: _puntosActuales,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
    // Auto-dismiss después de 2.5 s
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (entry.mounted) entry.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: CustomScrollView(
          slivers: [
            // ── Header ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    20, MediaQuery.of(context).padding.top + 16, 20, 20),
                color: cs.surface,
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PerfilScreen()),
                      ),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: cs.surfaceContainerHighest,
                        child: Text(_iniciales,
                            style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('¡Hola, ${_nombre.split(' ').first}!',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurfaceVariant)),
                          const Text('Tu estatus de hoy',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    // Badge de puntos — toca para ver tooltip
                    GestureDetector(
                      onTap: () => _mostrarTooltipPuntos(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.monetization_on,
                                size: 18, color: Color(0xFFD97706)),
                            const SizedBox(width: 6),
                            Text(
                              _loading ? '—' : _fmt(_puntosActuales),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Stats tappables ────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    _statCard(
                      icono: Icons.emoji_events_rounded,
                      colorFondo: const Color(0xFFFEF3C7),
                      colorIcono: const Color(0xFFD97706),
                      valor: _rankingPos != null ? '$_rankingPos° lugar' : '—',
                      label: 'Ranking',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RankingScreen(standalone: true)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _statCard(
                      icono: Icons.local_fire_department_rounded,
                      colorFondo: const Color(0xFFFFE4E4),
                      colorIcono: const Color(0xFFEF4444),
                      valor: '$_rachaDias días',
                      label: 'Racha',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RachaScreen()),
                      ).then((_) => _cargar()),
                    ),
                    const SizedBox(width: 10),
                    _statCard(
                      icono: Icons.workspace_premium_rounded,
                      colorFondo: const Color(0xFFEEF2FF),
                      colorIcono: const Color(0xFF6366F1),
                      valor: _nivel,
                      label: 'Nivel',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NivelScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Botón Iniciar viaje ────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Material(
                  color: const Color(0xFF1A6B47),
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: widget.onIniciarViaje,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                size: 34, color: Colors.white),
                          ),
                          const SizedBox(height: 14),
                          const Text('INICIAR VIAJE',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Retos activos ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Retos activos',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    if (!_loading && _viajesAnalizados == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Completa viajes para desbloquear',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    _retoCard(
                      titulo: 'Cero frenadas bruscas',
                      subtitulo: '',
                      progreso: _viajesSinFrenazos,
                      meta: _viajesAnalizados > 0 ? _viajesAnalizados : 5,
                    ),
                    const SizedBox(height: 10),
                    _retoCard(
                      titulo: 'Respetar semáforos',
                      subtitulo: '',
                      progreso: _senalesRespetadas,
                      meta: _metaSenales > 0 ? _metaSenales : 5,
                    ),
                    const SizedBox(height: 10),
                    _retoCard(
                      titulo: 'Conductor semanal',
                      subtitulo: 'Viajes completados esta semana',
                      progreso: _viajesEstaSemana,
                      meta: _metaViajesSemana,
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Widgets ─────────────────────────────────────────────────────────────

  Widget _statCard({
    required IconData icono,
    required Color colorFondo,
    required Color colorIcono,
    required String valor,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant, width: 0.8),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: colorFondo,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icono, color: colorIcono, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                _loading ? '—' : valor,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _retoCard({
    required String titulo,
    required String subtitulo,
    required int progreso,
    required int meta,
  }) {
    final cs          = Theme.of(context).colorScheme;
    final completado  = progreso >= meta && meta > 0;
    final fraccion    = meta > 0 ? (progreso / meta).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: completado ? const Color(0xFF1A6B47) : cs.outlineVariant,
          width: completado ? 1.5 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              Text('$progreso/$meta',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: completado
                          ? const Color(0xFF1A6B47)
                          : cs.onSurfaceVariant)),
            ],
          ),
          if (subtitulo.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitulo,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraccion,
              minHeight: 7,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF22C55E)),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}

// ── Tooltip flotante ────────────────────────────────────────────────────────
class _TooltipPuntos extends StatefulWidget {
  final int puntos;
  final VoidCallback onDismiss;
  const _TooltipPuntos({required this.puntos, required this.onDismiss});

  @override
  State<_TooltipPuntos> createState() => _TooltipPuntosState();
}

class _TooltipPuntosState extends State<_TooltipPuntos>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 62,
      right: 16,
      child: FadeTransition(
        opacity: _opacity,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF92400E),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Puntos ChillDrive',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.puntos} pts acumulados',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Data class para info de un reto completado ───────────────────────────────
class _RetoInfo {
  final String   nombre;
  final IconData icono;
  final Color    color;
  const _RetoInfo(this.nombre, this.icono, this.color);
}

// ── Diálogo de celebración ───────────────────────────────────────────────────
class _CelebracionDialog extends StatefulWidget {
  final List<_RetoInfo> retos;
  const _CelebracionDialog({required this.retos});

  @override
  State<_CelebracionDialog> createState() => _CelebracionDialogState();
}

class _CelebracionDialogState extends State<_CelebracionDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _bounce;
  int _indice = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _bounce = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();

    // Auto-avanzar o cerrar cada 3.5 s
    Future.delayed(const Duration(milliseconds: 3500), _siguiente);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _siguiente() {
    if (!mounted) return;
    if (_indice < widget.retos.length - 1) {
      _ctrl.reverse().then((_) {
        if (mounted) setState(() => _indice++);
        _ctrl.forward();
        Future.delayed(const Duration(milliseconds: 3500), _siguiente);
      });
    } else {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final reto = widget.retos[_indice];

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ScaleTransition(
        scale: _bounce,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                  color: reto.color.withValues(alpha: 0.25),
                  blurRadius: 30,
                  spreadRadius: 4),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ícono con fondo de color
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: reto.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.emoji_events_rounded,
                    size: 42, color: reto.color),
              ),
              const SizedBox(height: 16),

              const Text('¡Reto completado!',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: Colors.grey)),
              const SizedBox(height: 8),

              Text(
                reto.nombre,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(reto.icono, size: 16, color: reto.color),
                  const SizedBox(width: 6),
                  Text('Meta alcanzada',
                      style: TextStyle(fontSize: 13, color: reto.color)),
                ],
              ),

              // Indicador si hay varios retos
              if (widget.retos.length > 1) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.retos.length,
                    (i) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _indice ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _indice
                            ? reto.color
                            : cs.outlineVariant,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _siguiente,
                  style: FilledButton.styleFrom(
                      backgroundColor: reto.color,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: Text(
                    _indice < widget.retos.length - 1
                        ? 'Siguiente ›'
                        : '¡Genial!',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
