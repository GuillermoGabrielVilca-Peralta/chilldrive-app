import 'package:flutter/material.dart';
import '../api_service.dart';

class RankingScreen extends StatefulWidget {
  final bool standalone;
  const RankingScreen({super.key, this.standalone = false});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  final _api = ApiService();
  List<dynamic> _ranking = [];
  int? _miId;
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
      final uid  = await _api.getUsuarioId();
      final data = await _api.getRanking();

      // Ordenar client-side por puntosActuales DESC para garantizar el orden correcto
      final ordenado = List.of(data)
        ..sort((a, b) =>
            ((b['puntosActuales'] as int?) ?? 0)
                .compareTo((a['puntosActuales'] as int?) ?? 0));

      if (mounted) setState(() { _ranking = ordenado; _miId = uid; });
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
    } else if (_ranking.isEmpty) {
      body = _centrado(
          Icons.emoji_events_outlined,
          'Aún no hay conductores en el ranking.',
          _cargar);
    } else {
      body = RefreshIndicator(
        onRefresh: _cargar,
        child: CustomScrollView(
          slivers: [
            // ── Podio ─────────────────────────────────────────────
            if (_ranking.length >= 3)
              SliverToBoxAdapter(child: _podio(cs)),

            // ── Lista ─────────────────────────────────────────────
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

    if (widget.standalone) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ranking')),
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text('Ranking',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  // ── Podio (top 3) ──────────────────────────────────────────────────────
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
          // 2° lugar (izquierda, más bajo)
          Expanded(child: _podioItem(p2, 2, 90, cs)),
          const SizedBox(width: 8),
          // 1° lugar (centro, más alto)
          Expanded(child: _podioItem(p1, 1, 120, cs)),
          const SizedBox(width: 8),
          // 3° lugar (derecha, más bajo)
          Expanded(child: _podioItem(p3, 3, 76, cs)),
        ],
      ),
    );
  }

  Widget _podioItem(
      Map<String, dynamic> r, int pos, double altura, ColorScheme cs) {
    final nombre  = r['conductor'] as String? ?? '—';
    final puntos  = r['puntosActuales'] as int? ?? 0;
    final esYo    = r['usuarioId'] == _miId;
    final colores = _coloresPodio(pos);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Corona / trofeo
        Icon(_iconPodio(pos), size: 22, color: colores.$1),
        const SizedBox(height: 4),
        // Avatar
        CircleAvatar(
          radius: pos == 1 ? 28 : 22,
          backgroundColor: esYo ? cs.primary : colores.$1.withValues(alpha: 0.3),
          child: Text(
            _iniciales(nombre),
            style: TextStyle(
              fontSize: pos == 1 ? 16 : 13,
              fontWeight: FontWeight.bold,
              color: esYo ? cs.onPrimary : colores.$1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          nombre.split(' ').first,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          '$puntos pts',
          style: TextStyle(fontSize: 10, color: colores.$1),
        ),
        const SizedBox(height: 6),
        // Pedestal
        Container(
          height: altura,
          decoration: BoxDecoration(
            color: colores.$1.withValues(alpha: 0.25),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Center(
            child: Text(
              '$pos°',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colores.$1),
            ),
          ),
        ),
      ],
    );
  }

  // ── Tarjeta de lista ──────────────────────────────────────────────────
  Widget _tarjetaRanking(int i, ColorScheme cs) {
    final r    = _ranking[i] as Map<String, dynamic>;
    final uid  = r['usuarioId'] as int?;
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
                ? Icon(Icons.emoji_events,
                    color: _coloresPodio(pos).$1, size: 24)
                : Text('$pos°',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 18,
            backgroundColor:
                esYo ? cs.primary : cs.surfaceContainerHighest,
            child: Text(
              _iniciales(r['conductor'] as String? ?? '?'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: esYo ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r['conductor'] as String? ?? '—',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: esYo
                            ? cs.onPrimaryContainer
                            : cs.onSurface)),
                Text(r['tipoConductor'] as String? ?? '',
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
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
                  style:
                      TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

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
              TextButton(
                  onPressed: retry, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
}
