import 'package:flutter/material.dart';
import '../api_service.dart';
import '../utils/validaciones.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _api = ApiService();
  final _nombresCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _tipoConductor = 'Particular';
  bool _loading = false;
  bool _verPassword = false;
  String? _error;

  static const _tiposConductor = [
    'Particular', 'Taxi', 'Delivery', 'Mototaxi', 'Otro',
  ];

  @override
  void dispose() {
    _nombresCtrl.dispose();
    _apellidosCtrl.dispose();
    _correoCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    final nombres = _nombresCtrl.text.trim();
    final apellidos = _apellidosCtrl.text.trim();
    final correo = _correoCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (nombres.isEmpty || apellidos.isEmpty || correo.isEmpty || password.isEmpty) {
      setState(() => _error = 'Completa todos los campos.');
      return;
    }
    if (!esCorreoValido(correo)) {
      setState(() => _error = 'Ingresa un correo electrónico válido.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'La contraseña debe tener al menos 8 caracteres.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await _api.registro(
        nombres: nombres,
        apellidos: apellidos,
        correo: correo,
        password: password,
        tipoConductor: _tipoConductor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Cuenta creada! Inicia sesión.'),
          backgroundColor: Colors.teal,
        ),
      );
      Navigator.of(context).pop(); // vuelve a LoginScreen
    } catch (e) {
      setState(() => _error = mensajeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Crear cuenta'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: cs.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _campo('Nombres', _nombresCtrl,
                        icon: Icons.person_outlined,
                        action: TextInputAction.next),
                    const SizedBox(height: 14),
                    _campo('Apellidos', _apellidosCtrl,
                        icon: Icons.person_outline,
                        action: TextInputAction.next),
                    const SizedBox(height: 14),
                    _campo('Correo electrónico', _correoCtrl,
                        icon: Icons.email_outlined,
                        type: TextInputType.emailAddress,
                        action: TextInputAction.next),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: !_verPassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _registrar(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña (mín. 8 caracteres)',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_verPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () =>
                              setState(() => _verPassword = !_verPassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Tipo de conductor',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _tipoConductor,
                          isDense: true,
                          isExpanded: true,
                          items: _tiposConductor
                              .map((t) => DropdownMenuItem(
                                  value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) => setState(
                              () => _tipoConductor = v ?? 'Particular'),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!,
                            style: TextStyle(
                                color: cs.onErrorContainer, fontSize: 13)),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _registrar,
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Crear cuenta',
                              style: TextStyle(fontSize: 15)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(
    String label,
    TextEditingController ctrl, {
    required IconData icon,
    TextInputType type = TextInputType.text,
    TextInputAction action = TextInputAction.next,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: type,
        textInputAction: action,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      );
}
