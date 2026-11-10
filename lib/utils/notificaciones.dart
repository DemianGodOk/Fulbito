import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> inicializarNotificaciones() async {
  if (kIsWeb) return;
  tz.initializeTimeZones();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  final androidImpl = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.requestNotificationsPermission();
}

Future<void> mostrarNotificacion({
  required int id,
  required String titulo,
  required String cuerpo,
}) async {
  if (kIsWeb) return;

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'fulbito_notif_channel',
    'Avisos de Partidos',
    channelDescription:
        'Notificaciones sobre convocatorias y estado del equipo',
    importance: Importance.max,
    priority: Priority.high,
    styleInformation: BigTextStyleInformation(''),
  );

  const NotificationDetails details = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    id,
    titulo,
    cuerpo,
    details,
  );
}

Future<void> programarRecordatorioAsistencia({
  required DateTime fechaHora,
  required String partidoTexto,
}) async {
  if (kIsWeb) return;
  if (fechaHora.isBefore(DateTime.now())) return;

  try {
    await flutterLocalNotificationsPlugin.zonedSchedule(
      900,
      '⚽ Recordatorio de Asistencia Fulbito',
      'Recordá confirmar si jugás el $partidoTexto.',
      tz.TZDateTime.from(fechaHora, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'fulbito_recordatorios_channel',
          'Recordatorios Programados',
          channelDescription: 'Recordatorio programado para confirmar asistencia',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  } catch (e) {
    debugPrint('Error al programar recordatorio: $e');
  }
}
