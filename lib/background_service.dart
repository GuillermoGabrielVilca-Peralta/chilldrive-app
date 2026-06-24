import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// Entry point del foreground service.
// Debe estar fuera de main.dart y deteccion_screen.dart para evitar
// dependencias circulares. Android lanza este callback en un isolate
// separado cuando el servicio arranca en segundo plano.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ViajeTaskHandler());
}

class ViajeTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationButtonPressed(String id) {
    FlutterForegroundTask.sendDataToMain({'accion': id});
  }
}
