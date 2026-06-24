import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  static const _storage = FlutterSecureStorage();
  static const _keyNotif = 'notificaciones_activas';
  static const _version  = '1.0.0';

  bool _notificaciones = true;
  bool _cargando       = true;

  @override
  void initState() {
    super.initState();
    _cargarPreferencias();
  }

  Future<void> _cargarPreferencias() async {
    final val = await _storage.read(key: _keyNotif);
    if (mounted) {
      setState(() {
        _notificaciones = val != 'false'; // true por defecto
        _cargando = false;
      });
    }
  }

  Future<void> _toggleNotificaciones(bool valor) async {
    setState(() => _notificaciones = valor);
    await _storage.write(key: _keyNotif, value: valor.toString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(valor
              ? 'Notificaciones activadas'
              : 'Notificaciones desactivadas'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _mostrarIdioma() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Idioma'),
        content: const Text(
            'ChillDrive está disponible en español.\n\n'
            'Próximamente se agregarán más idiomas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  void _mostrarTextoLegal(String titulo, String contenido) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (_, controller) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(titulo,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    controller: controller,
                    children: [
                      Text(contenido,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            const Text('Configuración',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),

            // ── Sección: Aplicación ──────────────────────────────────
            _seccion('Aplicación', cs),
            _grupo([
              _tileSwitch(
                icon: Icons.notifications_outlined,
                label: 'Notificaciones',
                subtitulo: _notificaciones
                    ? 'Recibirás alertas de eventos y retos'
                    : 'Las alertas están desactivadas',
                valor: _notificaciones,
                onChanged: _toggleNotificaciones,
                cs: cs,
              ),
              _tile(
                icon: Icons.language_outlined,
                label: 'Idioma',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Español',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ],
                ),
                cs: cs,
                onTap: _mostrarIdioma,
              ),
            ], cs),

            const SizedBox(height: 20),

            // ── Sección: Privacidad ──────────────────────────────────
            _seccion('Privacidad', cs),
            _grupo([
              _tile(
                icon: Icons.privacy_tip_outlined,
                label: 'Política de privacidad',
                trailing:
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                cs: cs,
                onTap: () => _mostrarTextoLegal(
                    'Política de privacidad', _politicaPrivacidad),
              ),
              _tile(
                icon: Icons.description_outlined,
                label: 'Términos de servicio',
                trailing:
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                cs: cs,
                onTap: () => _mostrarTextoLegal(
                    'Términos de servicio', _terminosServicio),
              ),
            ], cs),

            const SizedBox(height: 20),

            // ── Sección: Acerca de ───────────────────────────────────
            _seccion('Acerca de', cs),
            _grupo([
              _tile(
                icon: Icons.info_outline,
                label: 'Versión',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_version,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onPrimaryContainer)),
                ),
                cs: cs,
              ),
              _tile(
                icon: Icons.directions_car_outlined,
                label: 'ChillDrive',
                trailing: Text('Sistema IA de conducción',
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant)),
                cs: cs,
              ),
              _tile(
                icon: Icons.school_outlined,
                label: 'Desarrollado en',
                trailing: Text('TECSUP',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant)),
                cs: cs,
              ),
            ], cs),
          ],
        ),
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────────────────

  Widget _seccion(String titulo, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(titulo,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.5)),
      );

  Widget _grupo(List<Widget> items, ColorScheme cs) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant, width: 0.8),
        ),
        child: Column(
          children: items
              .asMap()
              .entries
              .map((e) => Column(children: [
                    e.value,
                    if (e.key < items.length - 1)
                      Divider(height: 0, color: cs.outlineVariant),
                  ]))
              .toList(),
        ),
      );

  Widget _tile({
    required IconData icon,
    required String label,
    required Widget trailing,
    required ColorScheme cs,
    VoidCallback? onTap,
  }) =>
      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                  child:
                      Text(label, style: const TextStyle(fontSize: 14))),
              trailing,
            ],
          ),
        ),
      );

  Widget _tileSwitch({
    required IconData icon,
    required String label,
    required String subtitulo,
    required bool valor,
    required ValueChanged<bool> onChanged,
    required ColorScheme cs,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitulo,
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Switch(value: valor, onChanged: onChanged),
          ],
        ),
      );

  // ── Textos legales ────────────────────────────────────────────────────────

  static const _politicaPrivacidad = '''
ChillDrive recopila y procesa los siguientes datos personales:

1. DATOS RECOPILADOS
• Información de cuenta: nombre, correo electrónico y tipo de conductor.
• Datos de conducción: viajes realizados, eventos detectados por la cámara (semáforos, señales de velocidad, detección de peatones) y puntuaciones obtenidas.
• Datos de ubicación: velocidad GPS durante los viajes activos. No almacenamos rutas ni coordenadas precisas.
• Imágenes de la cámara: el procesamiento se realiza completamente en el dispositivo (on-device) usando modelos YOLO TFLite. Las imágenes no se envían ni almacenan en servidores.

2. USO DE LOS DATOS
Los datos se usan para calcular tu puntaje de conducción, gestionar puntos y canjes, y mostrarte estadísticas de progreso.

3. ALMACENAMIENTO
Los datos se almacenan en servidores seguros en Perú. Las credenciales se guardan localmente en almacenamiento seguro del dispositivo (flutter_secure_storage).

4. COMPARTICIÓN
No vendemos ni compartimos tus datos con terceros, salvo con los aliados participantes al momento de validar un canje (solo el código QR).

5. RETENCIÓN
Puedes solicitar la eliminación de tu cuenta y datos en cualquier momento contactando a soporte.

6. CONTACTO
Para consultas sobre privacidad: soporte@chilldrive.pe
''';

  static const _terminosServicio = '''
Al usar ChillDrive aceptas los siguientes términos:

1. USO DEL SERVICIO
ChillDrive es una plataforma de gamificación de conducción responsable. El servicio está disponible para conductores registrados en Perú.

2. CUENTA DE USUARIO
Eres responsable de mantener la confidencialidad de tu cuenta. Cada usuario puede tener una sola cuenta activa.

3. DETECCIÓN CON CÁMARA
La detección de eventos usa la cámara del dispositivo. Al activar un viaje autorizas el uso de la cámara con fines de detección de señales de tráfico. El procesamiento es local (on-device) y no se transmiten imágenes.

4. PUNTOS Y CANJES
• Los puntos ChillDrive no tienen valor monetario y no son transferibles.
• Los canjes de premios están sujetos a disponibilidad de los aliados.
• Los puntos obtenidos por viajes inválidos (menos de 5 minutos) no se acreditan.
• Un canje anulado devuelve los puntos en un plazo de 24 horas.

5. CONDUCCIÓN RESPONSABLE
ChillDrive promueve la conducción segura. No uses la app mientras manejas sin un soporte adecuado para el dispositivo. El conductor es siempre responsable de su vehículo.

6. MODIFICACIONES
Nos reservamos el derecho de modificar estos términos con previo aviso a los usuarios.

7. CONTACTO
soporte@chilldrive.pe
''';
}
