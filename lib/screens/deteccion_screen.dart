import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../api_service.dart';
import '../background_service.dart' show startCallback;


/// Pantalla de detección durante un viaje ACTIVO (recibe el viajeId + camaraId del home).
/// Soporta dos modelos intercambiables:
///   - Señales (default): semáforos + límites de velocidad → scoring por evento.
///   - Personas: YOLOv8n COCO → alerta de peatones (0 pts, aviso de seguridad).
class DeteccionScreen extends StatefulWidget {
  final int viajeId;
  final int camaraId;

  const DeteccionScreen({super.key, required this.viajeId, required this.camaraId});

  @override
  State<DeteccionScreen> createState() => _DeteccionScreenState();
}

class _DeteccionScreenState extends State<DeteccionScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();

  static const _pipControl = MethodChannel('chilldrive/pip');
  static const _pipStatusChannel = EventChannel('chilldrive/pip_status');
  StreamSubscription<dynamic>? _pipSub;
  bool _enPip = false;

  final FlutterTts _tts = FlutterTts();
  final Map<String, DateTime> _cooldownAudio = {};
  static const Duration _cooldownAudioDur = Duration(seconds: 10);
  int _conteoRiesgoPeatonal = 0;
  static const int _framesRiesgoPeatonal = 3;

  int _segundos = 0;
  Timer? _timer;
  bool _servicioActivo = false;
  int _segundosUltimaNotif = -30; // fuerza primera actualización

  static const int _minimoSegundos = 5 * 60; // 5 minutos

  int get _duracionMinutos => _segundos ~/ 60;
  bool get _superaMinimo   => _segundos >= _minimoSegundos;

  String get _timerStr {
    final m = (_segundos ~/ 60).toString().padLeft(2, '0');
    final s = (_segundos % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // Alerta visual
  late final AnimationController _alertController;
  late final Animation<double> _alertOpacity;
  Color _alertColor = Colors.green;

  bool? _permisoCamara;
  double _kmh = 0;
  // Modo prueba: velocidad manual para demostrar sin moverse.
  bool _usarSimulada = false;
  double _velSimulada = 0;
  double get _velActual => _usarSimulada ? _velSimulada : _kmh;

  // Modo de detección
  bool _modoPersonas = false;
  static const _modeloSenales = 'assets/models/senales.tflite';
  // Para más velocidad en hardware limitado, cambia a: 'assets/models/senales_int8.tflite'
  static const _modeloPersonas = 'assets/models/personas.tflite';

  String _puntos = '—';
  String _ultimaDeteccion = '—';
  String _ultimoEvento = '—';

  static const int _framesConfirmacion = 5;
  String? _candidato;
  int _conteo = 0;
  final Map<String, DateTime> _cooldown = {};
  static const Duration _cooldownDur = Duration(seconds: 6);

  StreamSubscription<Position>? _gpsSub;

  @override
  void initState() {
    super.initState();
    _alertController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _alertOpacity = Tween<double>(begin: 0.45, end: 0.0).animate(
      CurvedAnimation(parent: _alertController, curve: Curves.easeOut),
    );
    FlutterForegroundTask.addTaskDataCallback(_onMensajeTarea);
    _pipSub = _pipStatusChannel.receiveBroadcastStream().listen((inPip) {
      if (mounted) setState(() => _enPip = inPip as bool);
    });
    _inicializar();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _segundos++);
      // Actualiza notificación cada 5 segundos
      if (_servicioActivo && (_segundos - _segundosUltimaNotif) >= 5) {
        _segundosUltimaNotif = _segundos;
        _actualizarNotificacion();
      }
    });
  }

  // ── Callback del foreground service ──────────────────────────────────────

  void _onMensajeTarea(Object data) {
    if (data is! Map) return;
    final accion = data['accion'] as String?;
    if (!mounted) return;
    if (accion == 'btn_finalizar') {
      _finalizarViaje();
    }
  }

  // ── Foreground service ────────────────────────────────────────────────────

  static void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'chilldrive_viaje',
        channelName: 'Viaje ChillDrive',
        channelDescription: 'Detección activa de señales de tráfico.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.DEFAULT,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: false,
        autoRunOnBoot: false,
      ),
    );
  }

  Future<void> _iniciarServicioBackground() async {
    _initForegroundTask();
    final notifStatus = await FlutterForegroundTask.requestNotificationPermission();
    debugPrint('[ChillDrive] Notif permission: $notifStatus');
    try {
      await FlutterForegroundTask.startService(
        serviceId: 1001,
        notificationTitle: '🟢 Viaje #${widget.viajeId} en curso',
        notificationText: '⏱ 00:00  ·  Iniciando detección de señales...',
        notificationButtons: [
          const NotificationButton(id: 'btn_finalizar', text: '⏹ Finalizar'),
        ],
        callback: startCallback,
      );
      _servicioActivo = true;
      debugPrint('[ChillDrive] Foreground service iniciado correctamente');
    } catch (e) {
      debugPrint('[ChillDrive] ERROR al iniciar foreground service: $e');
    }
    await WakelockPlus.enable();
    try {
      await _pipControl.invokeMethod('setAutoEnter', true);
    } catch (_) {}
  }

  Future<void> _detenerServicioBackground() async {
    try {
      await _pipControl.invokeMethod('setAutoEnter', false);
    } catch (_) {}
    if (_servicioActivo) {
      await FlutterForegroundTask.stopService();
      _servicioActivo = false;
    }
    await WakelockPlus.disable();
  }

  Future<void> _actualizarNotificacion() async {
    if (!_servicioActivo) return;
    final pts = _puntos == '—' ? '0' : _puntos;
    final estado = _superaMinimo
        ? '✅ Viaje válido'
        : '${((_minimoSegundos - _segundos) / 60).ceil()} min para validar';
    final String textoDeteccion;
    if (_ultimaDeteccion != '—') {
      textoDeteccion = 'Viendo: $_ultimaDeteccion';
    } else if (_ultimoEvento != '—') {
      textoDeteccion = 'Último: $_ultimoEvento';
    } else {
      textoDeteccion = 'Detectando...';
    }
    await FlutterForegroundTask.updateService(
      notificationTitle: '🟢 Viaje #${widget.viajeId}  ·  $pts pts',
      notificationText: '⏱ $_timerStr  ·  $estado  ·  $textoDeteccion',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _inicializar() async {
    final cam = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _permisoCamara = cam.isGranted);
    if (!cam.isGranted) return;
    await _initTts();
    await _iniciarGps();
    await _refrescarPuntos();
    await _iniciarServicioBackground();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('es-ES');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _iniciarGps() async {
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        return;
      }
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).listen((pos) {
        final kmh = (pos.speed.isNaN ? 0.0 : pos.speed) * 3.6;
        if (mounted) setState(() => _kmh = kmh < 0 ? 0 : kmh);
      });
    } catch (_) {}
  }

  Future<void> _refrescarPuntos() async {
    try {
      final uid = await _api.getUsuarioId();
      final p = await _api.getPuntos(uid);
      if (mounted) {
        setState(() =>
            _puntos = p == null ? '0' : '${p['puntosActuales']} · ${p['nivel']}');
      }
    } catch (_) {}
  }

  // ── Lógica de eventos por modo ──────────────────────────────────────────────

  /// Modo señales: clase YOLO → TipoEvento del backend (o null si no aplica).
  String? _senalAEvento(String clase, double kmh) {
    if (clase == 'Green Light') return 'Señal Respetada';
    if (clase == 'Red Light') {
      return kmh > 5 ? 'Señal Ignorada' : 'Señal Respetada';
    }
    if (clase.startsWith('Speed Limit')) {
      final limite = int.tryParse(clase.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (limite > 0 && kmh > limite) return 'Exceso Velocidad';
      return null;
    }
    return null;
  }

  /// Modo personas (COCO): solo reacciona a peatones.
  String? _personaAEvento(String clase) {
    if (clase == 'person') return 'Peatón Detectado';
    return null;
  }

  bool _esPositivo(String tipo) =>
      tipo == 'Señal Respetada' ||
      tipo == 'Carril Mantenido' ||
      tipo == 'Distancia Segura';

  bool _esNeutro(String tipo) => tipo == 'Peatón Detectado';

  Color _colorDeEvento(String tipo) {
    if (_esPositivo(tipo)) return Colors.green;
    if (_esNeutro(tipo)) return Colors.orange;
    return Colors.red;
  }

  void _dispararAlerta(String tipo) {
    setState(() => _alertColor = _colorDeEvento(tipo));
    _alertController.forward(from: 0.0);
    if (_esPositivo(tipo)) {
      HapticFeedback.lightImpact();
    } else if (_esNeutro(tipo)) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  // ── Alertas de audio ──────────────────────────────────────────────────────

  Future<void> _hablarAlerta(String texto, String clave) async {
    final ahora = DateTime.now();
    final ultimo = _cooldownAudio[clave];
    if (ultimo != null && ahora.difference(ultimo) < _cooldownAudioDur) return;
    _cooldownAudio[clave] = ahora;
    await _tts.stop();
    await _tts.speak(texto);
  }

  void _alertaAudio(String clase) {
    final kmh = _velActual;

    if (clase == 'Red Light') {
      if (kmh > 5) {
        _hablarAlerta('Semáforo en rojo adelante, reduce la velocidad', 'rojo');
      }
      return;
    }

    if (clase.startsWith('Speed Limit')) {
      final limite = int.tryParse(clase.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (limite <= 0) return;
      if (kmh > limite + 5) {
        _hablarAlerta(
          'Exceso de velocidad. Límite $limite kilómetros por hora',
          'exceso_$limite',
        );
      } else {
        _hablarAlerta('Zona de $limite kilómetros por hora', 'zona_$limite');
      }
      return;
    }

    // Personas: manejado por _mensajeRiesgoPeatonal / _procesarDetecciones
  }

  // ── Riesgo peatonal inteligente ───────────────────────────────────────────

  /// Evalúa si hay riesgo real de atropello según posición + tamaño del
  /// bounding box normalizado (0–1) y velocidad actual.
  /// Retorna el mensaje a hablar, o null si no hay riesgo.
  String? _mensajeRiesgoPeatonal(List<YOLOResult> personas, double kmh) {
    if (personas.isEmpty || kmh < 2) return null;

    // Muchas personas en campo: zona escolar / mercado → siempre avisar
    if (personas.length >= 3) {
      return kmh > 20
          ? 'Zona muy transitada. Reduce la velocidad'
          : null; // a velocidad muy baja no hace falta
    }

    int puntos = 0;
    for (final p in personas) {
      final box = p.normalizedBox;
      final centerX = (box.left + box.right) / 2;
      final altura  = box.height; // bottom - top (0–1)

      final centrado    = centerX >= 0.20 && centerX <= 0.80;
      final cercano     = altura > 0.28;
      final muyCercano  = altura > 0.48;

      if (muyCercano && centrado) { puntos += 4; }
      else if (cercano && centrado) { puntos += 2; }
      else if (centrado) { puntos += 1; }
      // Persona en el borde (vereda): 0 puntos → sin alerta
    }

    if (puntos == 0) return null;

    if (kmh > 35 && puntos >= 2) {
      return '¡Atención! Persona en la vía. Frena ahora';
    }
    if (puntos >= 4) {
      return 'Persona muy cerca en la vía. Reduce la velocidad';
    }
    if (puntos >= 2) {
      return 'Precaución, persona detectada en la vía';
    }
    return null;
  }

  // ── Detección YOLO ────────────────────────────────────────────────────────

  /// Callback compartido por el YOLOView del modo completo y del modo PiP.
  void _procesarDetecciones(List<YOLOResult> results) {
    final validos = results.where((r) => r.confidence >= 0.5).toList();

    if (validos.isEmpty) {
      if (_ultimaDeteccion != '—') setState(() => _ultimaDeteccion = '—');
      _conteoRiesgoPeatonal = 0;
      return;
    }

    if (_modoPersonas) {
      final personas = validos.where((r) => r.className == 'person').toList();

      // Evaluación de riesgo por posición/tamaño (3 frames de confirmación)
      final mensaje = _mensajeRiesgoPeatonal(personas, _velActual);
      if (mensaje != null) {
        _conteoRiesgoPeatonal++;
        if (_conteoRiesgoPeatonal >= _framesRiesgoPeatonal) {
          _conteoRiesgoPeatonal = 0;
          _hablarAlerta(mensaje, 'riesgo_peatonal');
        }
      } else {
        _conteoRiesgoPeatonal = 0;
      }

      if (personas.isNotEmpty) {
        final mejor = personas.reduce(
            (a, b) => a.confidence >= b.confidence ? a : b);
        _onDeteccion(mejor.className);
      } else {
        if (_ultimaDeteccion != '—') setState(() => _ultimaDeteccion = '—');
      }
      return;
    }

    // Modo señales: lógica existente
    final mejor =
        validos.reduce((a, b) => a.confidence >= b.confidence ? a : b);
    _onDeteccion(mejor.className);
  }

  void _onDeteccion(String clase) {
    if (_ultimaDeteccion != clase) {
      setState(() => _ultimaDeteccion = clase);
    }
    if (clase == _candidato) {
      _conteo++;
    } else {
      _candidato = clase;
      _conteo = 1;
    }
    if (_conteo < _framesConfirmacion) return;
    _conteo = 0;

    // Alerta de audio confirmada (cooldown propio, independiente del evento)
    _alertaAudio(clase);

    final tipo = _modoPersonas
        ? _personaAEvento(clase)
        : _senalAEvento(clase, _velActual);
    if (tipo == null) return;

    final ahora = DateTime.now();
    final ultimo = _cooldown[tipo];
    if (ultimo != null && ahora.difference(ultimo) < _cooldownDur) return;
    _cooldown[tipo] = ahora;

    _enviarEvento(tipo);
  }

  Future<void> _enviarEvento(String tipo) async {
    try {
      await _api.registrarEvento(widget.viajeId, widget.camaraId, tipo);
      await _refrescarPuntos();
      if (mounted) {
        setState(() => _ultimoEvento = tipo);
        _dispararAlerta(tipo);
      }
      // Notificación inmediata al detectar un evento
      _segundosUltimaNotif = _segundos;
      await _actualizarNotificacion();
    } catch (e) {
      if (mounted) setState(() => _ultimoEvento = 'Error: ${mensajeError(e)}');
    }
  }

  Future<void> _finalizarViaje() async {
    try {
      await _detenerServicioBackground();
      final mensaje = await _api.finalizarViaje(
        widget.viajeId,
        duracionMinutos: _duracionMinutos,
      );
      await _api.clearViajeActual();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Viaje finalizado'),
          content: Text(mensaje),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensajeError(e))));
      }
    }
  }

  Future<bool> _mostrarDialogoSalida() async {
    final opcion = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('¿Qué haces con el viaje?'),
        content: Text(
          _superaMinimo
              ? 'Llevas $_timerStr — el viaje ya es válido.\n¿Qué deseas hacer?'
              : 'Llevas $_timerStr — aún no alcanzas el mínimo de 5 min.\nSi finalizas ahora, el viaje se cancelará automáticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'continuar'),
            child: const Text('Seguir manejando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'dejar'),
            child: const Text('Dejar en curso'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancelar'),
            child: const Text('Cancelar viaje',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (opcion == 'cancelar') {
      await _detenerServicioBackground();
      try {
        await _api.cancelarViaje(widget.viajeId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Viaje cancelado. No cuenta para retos.')),
          );
        }
      } catch (_) {}
      return true; // salir
    }

    // "Dejar en curso": servicio sigue corriendo, notificación persiste
    if (opcion == 'dejar') return true;

    return false; // 'continuar' → no salir
  }

  void _toggleModo() {
    setState(() {
      _modoPersonas = !_modoPersonas;
      _candidato = null;
      _conteo = 0;
      _ultimaDeteccion = '—';
    });
  }

  @override
  void dispose() {
    _tts.stop();
    FlutterForegroundTask.removeTaskDataCallback(_onMensajeTarea);
    _pipSub?.cancel();
    _timer?.cancel();
    _alertController.dispose();
    _gpsSub?.cancel();
    if (!_servicioActivo) {
      WakelockPlus.disable();
    }
    super.dispose();
  }

  Widget _buildPipView() {
    final texto = _ultimaDeteccion != '—'
        ? _ultimaDeteccion
        : (_ultimoEvento != '—' ? _ultimoEvento : 'Detectando...');
    return Stack(
      fit: StackFit.expand,
      children: [
        YOLOView(
          key: ValueKey(_modoPersonas ? 'personas' : 'senales'),
          modelPath: _modoPersonas ? _modeloPersonas : _modeloSenales,
          task: YOLOTask.detect,
          onResult: _procesarDetecciones,
        ),
        AnimatedBuilder(
          animation: _alertOpacity,
          builder: (_, _) {
            if (_alertOpacity.value == 0) return const SizedBox.shrink();
            return Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: _alertColor.withValues(alpha: _alertOpacity.value),
                ),
              ),
            );
          },
        ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            color: Colors.black.withValues(alpha: 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _timerStr,
                  style: TextStyle(
                    color: _superaMinimo ? Colors.greenAccent : Colors.orangeAccent,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  texto,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_permisoCamara == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_permisoCamara == false) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detección')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Se necesita permiso de cámara.', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_enPip) return _buildPipView();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final salir = await _mostrarDialogoSalida();
        if (!salir || !mounted) return;
        // ignore: use_build_context_synchronously
        Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('Viaje #${widget.viajeId}'),
        actions: [
          TextButton.icon(
            onPressed: _finalizarViaje,
            icon: const Icon(Icons.stop_circle, color: Colors.white),
            label: const Text('Finalizar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Barra de estado ──────────────────────────────────────────────
          Container(
            color: Colors.teal.shade50,
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    _info('Velocidad',
                        '${_velActual.toStringAsFixed(0)} km/h${_usarSimulada ? ' (sim)' : ''}'),
                    _info('Puntos', _puntos),
                    _infoTimer(),
                  ],
                ),
                const SizedBox(height: 8),
                // ── Barra de progreso hacia los 5 min ──────────────────
                if (!_superaMinimo) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _segundos / _minimoSegundos,
                      minHeight: 5,
                      backgroundColor: Colors.teal.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.orange.shade600),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mínimo 5 min para que cuente · faltan ${((_minimoSegundos - _segundos) / 60).ceil()} min',
                    style: TextStyle(
                        fontSize: 10, color: Colors.orange.shade800),
                  ),
                  const SizedBox(height: 6),
                ] else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 1.0,
                      minHeight: 5,
                      backgroundColor: Colors.green.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.green.shade600),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '¡Viaje válido! Ya cuenta para retos y racha',
                    style: TextStyle(
                        fontSize: 10, color: Colors.green.shade800),
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          // ── Controles ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                // Toggle modo detección
                _modeChip(
                  icon: Icons.traffic,
                  label: 'Señales',
                  activo: !_modoPersonas,
                  onTap: _modoPersonas ? _toggleModo : null,
                ),
                const SizedBox(width: 8),
                _modeChip(
                  icon: Icons.directions_walk,
                  label: 'Personas',
                  activo: _modoPersonas,
                  onTap: _modoPersonas ? null : _toggleModo,
                ),
                const Spacer(),
                // Velocidad simulada
                const Text('Sim', style: TextStyle(fontSize: 12)),
                Switch(
                  value: _usarSimulada,
                  onChanged: (v) => setState(() => _usarSimulada = v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          if (_usarSimulada)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Slider(
                value: _velSimulada,
                min: 0,
                max: 120,
                divisions: 24,
                label: '${_velSimulada.toStringAsFixed(0)} km/h',
                onChanged: (v) => setState(() => _velSimulada = v),
              ),
            ),
          // ── Vista de cámara ───────────────────────────────────────────────
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // La Key fuerza la recarga del modelo al cambiar de modo
                YOLOView(
                  key: ValueKey(_modoPersonas ? 'personas' : 'senales'),
                  modelPath: _modoPersonas ? _modeloPersonas : _modeloSenales,
                  task: YOLOTask.detect,
                  onResult: _procesarDetecciones,
                ),
                // Flash de alerta: verde / naranja / rojo según el evento
                AnimatedBuilder(
                  animation: _alertOpacity,
                  builder: (_, _) {
                    if (_alertOpacity.value == 0) return const SizedBox.shrink();
                    return Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: _alertColor
                              .withValues(alpha: _alertOpacity.value),
                        ),
                      ),
                    );
                  },
                ),
                // Etiqueta inferior de estado
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.6),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _modoPersonas
                                  ? Icons.directions_walk
                                  : Icons.traffic,
                              color: Colors.white54,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _modoPersonas ? 'Modo personas' : 'Modo señales',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Detectando: $_ultimaDeteccion',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('Último evento: $_ultimoEvento',
                            style: const TextStyle(
                                color: Colors.amberAccent, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ), // Scaffold
    ); // PopScope
  }

  Widget _info(String titulo, String valor) => Expanded(
        child: Column(
          children: [
            Text(titulo,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            Text(valor,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _infoTimer() => Expanded(
        child: Column(
          children: [
            Text('Tiempo',
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _superaMinimo
                      ? Icons.check_circle
                      : Icons.timer_outlined,
                  size: 13,
                  color: _superaMinimo
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
                const SizedBox(width: 3),
                Text(
                  _timerStr,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _superaMinimo
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _modeChip({
    required IconData icon,
    required String label,
    required bool activo,
    VoidCallback? onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: activo ? Colors.teal : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: activo ? Colors.white : Colors.black54),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: activo ? Colors.white : Colors.black54,
                      fontWeight:
                          activo ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        ),
      );
}
