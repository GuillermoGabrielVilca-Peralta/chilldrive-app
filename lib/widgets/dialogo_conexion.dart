import 'package:flutter/material.dart';
import '../api_service.dart';
import '../config/app_config.dart';

/// Diálogo reutilizable para ver/cambiar la URL del backend y probar la conexión.
/// Accesible desde el login (antes de entrar, cuando no se puede conectar) y desde
/// Configuración. Aplica el cambio sobre el [api] recibido, así el mismo cliente
/// que hace login/peticiones queda apuntando a la nueva URL sin recrearse.
Future<void> mostrarDialogoConexion(BuildContext context, ApiService api) async {
  final controller = TextEditingController(text: api.baseUrl);
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      String? estado; // null | 'probando' | 'ok' | 'fail'
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> guardarYProbar() async {
            final url = controller.text.trim();
            if (url.isEmpty) return;
            setLocal(() => estado = 'probando');
            await api.setBaseUrl(url);
            final ok = await api.probarConexion();
            if (!ctx.mounted) return;
            setLocal(() => estado = ok ? 'ok' : 'fail');
          }

          Future<void> restablecer() async {
            await AppConfig.restablecer();
            await api.setBaseUrl(AppConfig.apiBaseUrlPorDefecto);
            controller.text = AppConfig.apiBaseUrlPorDefecto;
            setLocal(() => estado = null);
          }

          return AlertDialog(
            title: const Text('Servidor backend'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'IP y puerto del servidor ChillDrive. El celular y la PC '
                  'deben estar en el mismo WiFi.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    hintText: 'http://192.168.1.10:5126',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (estado != null) ...[
                  const SizedBox(height: 14),
                  _estadoConexion(estado!),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: estado == 'probando' ? null : restablecer,
                child: const Text('Restablecer'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
              FilledButton(
                onPressed: estado == 'probando' ? null : guardarYProbar,
                child: const Text('Guardar y probar'),
              ),
            ],
          );
        },
      );
    },
  );
}

Widget _estadoConexion(String estado) {
  switch (estado) {
    case 'probando':
      return const Row(
        children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Probando conexión…', style: TextStyle(fontSize: 13)),
        ],
      );
    case 'ok':
      return const Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 18),
          SizedBox(width: 8),
          Text('Conectado correctamente',
              style: TextStyle(fontSize: 13, color: Colors.green)),
        ],
      );
    default:
      return const Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text('Sin respuesta del servidor. Revisa la IP y el WiFi.',
                style: TextStyle(fontSize: 13, color: Colors.red)),
          ),
        ],
      );
  }
}
