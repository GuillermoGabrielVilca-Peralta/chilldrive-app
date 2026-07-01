import 'package:flutter/material.dart';
import '../api_service.dart';
import 'login_screen.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _api = ApiService();
  String _nombreCompleto = '';
  String _tipoConductor = '';
  bool _loading = true;

  // Estadísticas de conducción (se cargan del backend; no bloquean el perfil).
  int _puntos = 0;
  int _historico = 0;
  String _nivel = '—';
  int _score = 100;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _loading = true);
    final nombre = await _api.getNombreCompleto();
    final tipo = await _api.getTipoConductor();

    // Puntos + score del backend. Si no hay red, el perfil igual muestra nombre/tipo.
    var puntos = 0, historico = 0, score = 100;
    var nivel = '—';
    try {
      final uid = await _api.getUsuarioId();
      final p = await _api.getPuntos(uid);
      if (p != null) {
        puntos = (p['puntosActuales'] as int?) ?? 0;
        historico = (p['puntosHistoricos'] as int?) ?? 0;
        nivel = (p['nivel'] as String?) ?? '—';
      }
      final e = await _api.getEstadisticasConduccion(uid);
      score = (e['scoreGeneral'] as int?) ?? 100;
    } catch (_) {
      // Sin conexión: se mantienen los valores por defecto.
    }

    if (mounted) {
      setState(() {
        _nombreCompleto = nombre;
        _tipoConductor = tipo;
        _puntos = puntos;
        _historico = historico;
        _nivel = nivel;
        _score = score;
        _loading = false;
      });
    }
  }

  /// Formatea un entero con separador de miles (1250 → "1,250") sin depender de intl.
  static String _fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      );

  String get _iniciales {
    final partes = _nombreCompleto.trim().split(' ');
    if (partes.length >= 2) {
      return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
    }
    return _nombreCompleto.isNotEmpty
        ? _nombreCompleto[0].toUpperCase()
        : '?';
  }

  Future<void> _editarPerfil() async {
    final nombreCtrl = TextEditingController(text: _nombreCompleto);
    final tipoCtrl   = TextEditingController(text: _tipoConductor);

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Editar perfil',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: nombreCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: tipoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tipo de conductor',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Guardar cambios',
                        style: TextStyle(fontSize: 15)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancelar',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (guardado != true || !mounted) return;

    final nuevoNombre = nombreCtrl.text.trim();
    final nuevoTipo   = tipoCtrl.text.trim();
    if (nuevoNombre.isEmpty) return;

    try {
      final uid = await _api.getUsuarioId();
      await _api.put('/usuario/$uid', {
        'nombreCompleto': nuevoNombre,
        'tipoConductor': nuevoTipo,
      });
    } catch (_) {
      // Si el endpoint falla, igual actualizamos la vista local
    }

    await _api.setNombreCompleto(nuevoNombre);
    await _api.setTipoConductor(nuevoTipo);

    if (mounted) {
      setState(() {
        _nombreCompleto = nuevoNombre;
        _tipoConductor  = nuevoTipo;
      });
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content:
            const Text('¿Estás seguro de que quieres cerrar sesión?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cerrar sesión',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _api.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      backgroundColor: cs.surfaceContainerLowest,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── Avatar + nombre ──────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: cs.primaryContainer,
                        child: Text(
                          _iniciales,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _nombreCompleto,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _tipoConductor,
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Estadísticas de conducción ───────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _statMetrica('Puntos', _fmt(_puntos))),
                          _statDivider(),
                          Expanded(child: _statMetrica('Nivel', _nivel)),
                          _statDivider(),
                          Expanded(child: _statMetrica('Score', '$_score/100')),
                        ],
                      ),
                      if (_historico > 0) ...[
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white24, height: 1),
                        const SizedBox(height: 12),
                        Text(
                          '${_fmt(_historico)} puntos ganados en total',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Info card ────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      _fila(
                        icon: Icons.person_outline,
                        label: 'Nombre completo',
                        valor: _nombreCompleto,
                        cs: cs,
                        ultimo: false,
                      ),
                      _fila(
                        icon: Icons.directions_car_outlined,
                        label: 'Tipo de conductor',
                        valor: _tipoConductor,
                        cs: cs,
                        ultimo: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Editar perfil ────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _editarPerfil,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar perfil',
                        style: TextStyle(fontSize: 15)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Cerrar sesión ────────────────────────────────────────
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text('Cerrar sesión',
                      style: TextStyle(color: Colors.red, fontSize: 15)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
            ),
    );
  }

  Widget _statMetrica(String label, String valor) => Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(valor,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      );

  Widget _statDivider() =>
      Container(width: 1, height: 32, color: Colors.white24);

  Widget _fila({
    required IconData icon,
    required String label,
    required String valor,
    required ColorScheme cs,
    required bool ultimo,
  }) =>
      Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: cs.onSurfaceVariant, size: 20),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                    Text(valor,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ),
          if (!ultimo) Divider(height: 0, color: cs.outlineVariant),
        ],
      );
}
