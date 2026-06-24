import 'package:flutter/material.dart';
import '../api_service.dart';

class RankingScreen extends StatefulWidget {
  final bool standalone;
  const RankingScreen({super.key, this.standalone = false});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();

  // ── Tab Ranking ──────────────────────────────────────────────────────────
  List<dynamic> _ranking = [];
  int? _miId;

  // ── Tab Mi conducción ────────────────────────────────────────────────────
  Map<String, dynamic>? _stats;

  bool _loading = true;
  String? _error;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      final uid     = await _api.getUsuarioId();
      final ranking = await _api.getRanking();
      final stats   = await _api.getEstadisticasConduccion(uid);

      final ordenado = List.of(ranking)
        ..sort((a, b) =>
            ((b['puntosActuales'] as int?) ?? 0)
                .compareTo((a['puntosActuales'] as int?) ?? 0));

      if (mounted) {
        setState(() {
          _miId    = uid;
          _ranking = ordenado;
          _stats   = stats;
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

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _centrado(Icons.error_outline, _error!, _cargar);
    } else {
      body = TabBarView(
        controller: _tabController,
        children: [
          _tabRanking(cs),
          _tabConduccion(cs),
        ],
      );
    }

    if (widget.standalone) {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Ranking'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [Tab(text: 'Ranking'), Tab(text: 'Mi conducción')],
            ),
          ),
          backgroundColor: cs.surfaceContainerLowest,
          body: body,
        ),
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
              child: Text('Ranking',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [Tab(text: 'Ranking'), Tab(text: 'Mi conducción')],
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Ranking ────────────────────────────────────────────────────────

  Widget _tabRanking(ColorScheme cs) {
    if (_ranking.isEmpty) {
      return _centrado(
          Icons.emoji_events_outlined, 'Aún no hay conductores en el ranking.', _cargar);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: CustomScrollView(
        slivers: [
          if (_ranking.length >= 3)
            SliverToBoxAdapter(child: _podio(cs)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _tarjetaRanking(i, cs),
                ),
                childCount: _ranking.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Mi conducción ─────────────────────────────────────────────────

  Widget _tabConduccion(ColorScheme cs) {
    if (_stats == null) {
      return _centrado(Icons.bar_chart_outlined, 'Sin datos de conducción.', _cargar);
    }

    final scoreGeneral = _stats!['scoreGeneral'] as int? ?? 0;
    final categorias   = (_stats!['categorias'] as List?) ?? [];
    final totalNeg     = _stats!['totalEventosNegativos'] as int? ?? 0;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          // ── Score general ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A6B47), Color(0xFF0D4A32)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                _scoreCirculo(scoreGeneral, 56, 22, Colors.white, Colors.white54),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Score general',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(_nivelTexto(scoreGeneral),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('$totalNeg evento${totalNeg == 1 ? "" : "s"} negativo${totalNeg == 1 ? "" : "s"} acumulados',
                          style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Text('Hábitos de conducción',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          const SizedBox(height: 12),

          // ── Categorías ──────────────────────────────────────────────────
          ...categorias.map((cat) {
            final nombre   = cat['nombre'] as String? ?? '';
            final score    = cat['score'] as int? ?? 100;
            final cantidad = cat['cantidad'] as int? ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _tarjetaCategoria(nombre, score, cantidad, cs),
            );
          }),
        ],
      ),
    );
  }

  Widget _tarjetaCategoria(
      String nombre, int score, int cantidad, ColorScheme cs) {
    final color = _colorScore(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(_iconCategoria(nombre), size: 22, color: cs.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: cs.onSurface)),
                if (cantidad > 0)
                  Text('$cantidad evento${cantidad == 1 ? "" : "s"} detectado${cantidad == 1 ? "" : "s"}',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          _scoreCirculo(score, 36, 14, color, color.withValues(alpha: 0.3)),
        ],
      ),
    );
  }

  Widget _scoreCirculo(
      int score, double size, double fontSize, Color color, Color bg) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: score / 100,
            strokeWidth: size * 0.12,
            backgroundColor: bg,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Center(
            child: Text('$score',
                style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ),
        ],
      ),
    );
  }

  Color _colorScore(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  String _nivelTexto(int score) {
    if (score >= 90) return 'Conductor ejemplar';
    if (score >= 75) return 'Buena conducción';
    if (score >= 60) return 'Conducción regular';
    return 'Necesita mejorar';
  }

  IconData _iconCategoria(String nombre) => switch (nombre) {
        'Velocidad'   => Icons.speed,
        'Frenado'     => Icons.pan_tool_alt_outlined,
        'Aceleración' => Icons.keyboard_double_arrow_up,
        'Giros'       => Icons.turn_right,
        'Celular'     => Icons.smartphone,
        _             => Icons.bar_chart,
      };

  // ── Podio (top 3) ─────────────────────────────────────────────────────────
  Widget _podio(ColorScheme cs) {
    final p1 = _ranking[0] as Map<String, dynamic>;
    final p2 = _ranking[1] as Map<String, dynamic>;
    final p3 = _ranking[2] as Map<String, dynamic>;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A6B47), Color(0xFF0D4A32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _podioItem(p2, 2, 90, cs)),
          const SizedBox(width: 8),
          Expanded(child: _podioItem(p1, 1, 120, cs)),
          const SizedBox(width: 8),
          Expanded(child: _podioItem(p3, 3, 76, cs)),
        ],
      ),
    );
  }

  Widget _podioItem(Map<String, dynamic> r, int pos, double altura, ColorScheme cs) {
    final nombre = r['conductor'] as String? ?? '—';
    final puntos = r['puntosActuales'] as int? ?? 0;
    final esYo   = r['usuarioId'] == _miId;
    final color  = _coloresPodio(pos).$1;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(_iconPodio(pos), size: 22, color: color),
        const SizedBox(height: 4),
        CircleAvatar(
          radius: pos == 1 ? 28 : 22,
          backgroundColor: esYo ? cs.primary : color.withValues(alpha: 0.3),
          child: Text(_iniciales(nombre),
              style: TextStyle(
                  fontSize: pos == 1 ? 16 : 13,
                  fontWeight: FontWeight.bold,
                  color: esYo ? cs.onPrimary : color)),
        ),
        const SizedBox(height: 6),
        Text(nombre.split(' ').first,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text('$puntos pts', style: TextStyle(fontSize: 10, color: color)),
        const SizedBox(height: 6),
        Container(
          height: altura,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Center(
            child: Text('$pos°',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ),
        ),
      ],
    );
  }

  // ── Lista ranking ─────────────────────────────────────────────────────────
  Widget _tarjetaRanking(int i, ColorScheme cs) {
    final r   = _ranking[i] as Map<String, dynamic>;
    final uid = r['usuarioId'] as int?;
    final esYo = uid == _miId;
    final pos  = i + 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: esYo ? cs.primaryContainer : cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: esYo ? cs.primary : cs.outlineVariant,
          width: esYo ? 1.5 : 0.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: pos <= 3
                ? Icon(Icons.emoji_events, color: _coloresPodio(pos).$1, size: 24)
                : Text('$pos°',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 18,
            backgroundColor: esYo ? cs.primary : cs.surfaceContainerHighest,
            child: Text(_iniciales(r['conductor'] as String? ?? '?'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: esYo ? cs.onPrimary : cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r['conductor'] as String? ?? '—',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: esYo ? cs.onPrimaryContainer : cs.onSurface)),
                Text(r['tipoConductor'] as String? ?? '',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${r['puntosActuales'] ?? 0} pts',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: esYo ? cs.primary : cs.onSurface)),
              Text(r['nivel'] as String? ?? '',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  (Color, Color) _coloresPodio(int pos) => switch (pos) {
        1 => (const Color(0xFFD97706), const Color(0xFFFEF3C7)),
        2 => (const Color(0xFF94A3B8), const Color(0xFFF1F5F9)),
        _ => (const Color(0xFF92400E), const Color(0xFFFEF3C7)),
      };

  IconData _iconPodio(int pos) => switch (pos) {
        1 => Icons.emoji_events,
        2 => Icons.workspace_premium,
        _ => Icons.military_tech,
      };

  String _iniciales(String nombre) {
    final p = nombre.trim().split(' ');
    if (p.length >= 2) return '${p[0][0]}${p[1][0]}'.toUpperCase();
    return nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';
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
