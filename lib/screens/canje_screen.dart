import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../api_service.dart';

/// Pantalla de confirmación + QR tras un canje.
class CanjeScreen extends StatefulWidget {
  final Map<String, dynamic> premio;
  final int puntosActuales;

  const CanjeScreen({
    super.key,
    required this.premio,
    required this.puntosActuales,
  });

  @override
  State<CanjeScreen> createState() => _CanjeScreenState();
}

class _CanjeScreenState extends State<CanjeScreen> {
  final _api = ApiService();
  bool _canjeando = false;
  Map<String, dynamic>? _canje;
  String? _error;

  Future<void> _confirmar() async {
    setState(() { _canjeando = true; _error = null; });
    try {
      final uid = await _api.getUsuarioId();
      final result = await _api.canjear(uid, widget.premio['id'] as int);
      final canjeId = result['id'] as int;
      final canje = await _api.getCanjeById(canjeId);
      if (mounted) setState(() => _canje = canje);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeError(e));
    } finally {
      if (mounted) setState(() => _canjeando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final costo = widget.premio['puntosRequeridos'] as int? ?? 0;
    final saldoRestante = widget.puntosActuales - costo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Canjear premio'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, _canje != null),
        ),
      ),
      backgroundColor: cs.surfaceContainerLowest,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _canje == null ? _vistaConfirmacion(cs, costo, saldoRestante)
                              : _vistaQr(cs),
      ),
    );
  }

  Widget _vistaConfirmacion(ColorScheme cs, int costo, int saldoRestante) =>
      Column(
        children: [
          const SizedBox(height: 16),
          // Premio card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.card_giftcard,
                      color: cs.primary, size: 36),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.premio['nombre'] as String? ?? '—',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (widget.premio['descripcion'] != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.premio['descripcion'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  widget.premio['nombreAliado'] as String? ?? '',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.primary,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Resumen de puntos
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: [
                _filaResumen('Tus puntos', '${widget.puntosActuales}',
                    cs.onSurface),
                const Divider(height: 20),
                _filaResumen('Costo del premio', '− $costo pts',
                    Colors.red),
                const Divider(height: 20),
                _filaResumen('Quedarán', '$saldoRestante pts',
                    cs.primary, bold: true),
              ],
            ),
          ),
          const SizedBox(height: 28),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style: TextStyle(color: cs.onErrorContainer)),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _canjeando ? null : _confirmar,
              child: _canjeando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Confirmar canje',
                      style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      );

  Widget _vistaQr(ColorScheme cs) {
    final qr = _canje!['codigoQr'] as String? ?? '';
    return Column(
      children: [
        const SizedBox(height: 16),
        Icon(Icons.check_circle, color: cs.primary, size: 52),
        const SizedBox(height: 12),
        const Text('¡Canje exitoso!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          'Muestra este QR al establecimiento',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: QrImageView(
            data: qr.isEmpty ? 'CHILLDRIVE-${_canje!['id']}' : qr,
            version: QrVersions.auto,
            size: 220,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 20),
        // Info del canje
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            children: [
              _filaResumen('Premio',
                  _canje!['nombrePremio'] as String? ?? '—', cs.onSurface),
              const SizedBox(height: 6),
              _filaResumen('Aliado',
                  _canje!['nombreAliado'] as String? ?? '—', cs.onSurface),
              const SizedBox(height: 6),
              _filaResumen('Puntos usados',
                  '${_canje!['puntosUtilizados'] ?? 0}', cs.onSurface),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Listo'),
          ),
        ),
      ],
    );
  }

  Widget _filaResumen(String label, String valor, Color valorColor,
      {bool bold = false}) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(valor,
              style: TextStyle(
                  fontSize: 14,
                  color: valorColor,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      );
}
