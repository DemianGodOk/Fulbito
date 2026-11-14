import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'fcm_auth_stub.dart' if (dart.library.io) 'fcm_auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/jugador.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

bool gEnPantallaVestuario = false;

String? _cachedFcmToken;
DateTime? _cachedFcmTokenExpiry;
Map<String, dynamic>? _cachedServiceAccountJson;

void _configurarZonaHorariaLocal() {
  tz.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation('America/Argentina/Buenos_Aires'));
  } catch (_) {}
}

Future<void> _inicializarPluginLocal() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  try {
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    final androidImpl = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          'fulbito_notif_channel',
          'Avisos de Partidos',
          description: 'Notificaciones sobre convocatorias y estado del equipo',
          importance: Importance.max,
        ),
      );
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          'fulbito_chat_channel',
          'Chat del Vestuario',
          description: 'Mensajes nuevos enviados al chat del vestuario',
          importance: Importance.max,
        ),
      );
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          'fulbito_recordatorios_channel',
          'Recordatorios Programados',
          description: 'Recordatorio semanal para confirmar asistencia',
          importance: Importance.max,
        ),
      );
    }
  } catch (e) {
    debugPrint('Error al inicializar plugin local: $e');
  }
}

Future<void> inicializarNotificaciones() async {
  if (kIsWeb) return;

  _configurarZonaHorariaLocal();
  await _inicializarPluginLocal();

  try {
    final androidImpl = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
  } catch (e) {
    debugPrint('Error pidiendo permisos locales: $e');
  }

  try {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      procesarMensajePush(message, enPrimerPlano: true);
    });
  } catch (e) {
    debugPrint('Error al inicializar FCM: $e');
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  _configurarZonaHorariaLocal();
  await _inicializarPluginLocal();
  await procesarMensajePush(message, enPrimerPlano: false);
}

Future<bool> marcarNotificacionComoMostrada(int id) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final lista = prefs.getStringList('notifs_mostradas_ids') ?? [];
    final idStr = '$id';
    if (lista.contains(idStr)) return false;

    lista.add(idStr);
    if (lista.length > 60) {
      lista.removeRange(0, lista.length - 60);
    }
    await prefs.setStringList('notifs_mostradas_ids', lista);
    return true;
  } catch (e) {
    return false;
  }
}

Future<void> procesarMensajePush(
  RemoteMessage message, {
  required bool enPrimerPlano,
}) async {
  if (kIsWeb) return;

  final data = message.data;
  if (data.isEmpty) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final String miAlias = prefs.getString('alias_usuario') ?? '';
    final String tipo = (data['tipo'] ?? '').toString();
    final int notifId = int.tryParse((data['notifId'] ?? '').toString()) ??
        (DateTime.now().millisecondsSinceEpoch % 100000000);

    if (tipo == 'chat') {
      final bool chatHabilitado = prefs.getBool('notif_chat_habilitada') ?? true;
      if (!chatHabilitado) return;

      final String autor = (data['autor'] ?? '').toString();
      final String texto = (data['texto'] ?? '').toString();
      if (texto.isEmpty) return;

      if (miAlias.isNotEmpty && sonElMismoJugador(autor, miAlias)) return;
      if (enPrimerPlano && gEnPantallaVestuario) return;

      final esNueva = await marcarNotificacionComoMostrada(notifId);
      if (!esNueva) return;

      await mostrarNotificacion(
        id: notifId,
        titulo: '💬 $autor (Vestuario)',
        cuerpo: texto,
        canalId: 'fulbito_chat_channel',
        canalNombre: 'Chat del Vestuario',
      );
    } else if (tipo == 'asistencia') {
      final bool soyAdmin = prefs.getBool('es_admin') ?? false;
      if (!soyAdmin) return;

      final String nombre = (data['nombre'] ?? '').toString();
      final String estado = (data['estado'] ?? '').toString();
      if (nombre.isEmpty) return;

      if (miAlias.isNotEmpty && sonElMismoJugador(nombre, miAlias)) return;

      final esNueva = await marcarNotificacionComoMostrada(notifId);
      if (!esNueva) return;

      if (estado == 'confirmado') {
        await mostrarNotificacion(
          id: notifId,
          titulo: '✅ Confirmación de asistencia',
          cuerpo: '$nombre confirmó que va a jugar este partido.',
        );
      } else if (estado == 'baja') {
        await mostrarNotificacion(
          id: notifId,
          titulo: '⚠️ Baja registrada',
          cuerpo: '$nombre avisó que no juega este partido.',
        );
      }
    }
  } catch (e) {
    debugPrint('Error procesando mensaje push: $e');
  }
}

Future<void> configurarSuscripcionesNotificaciones({
  required String alias,
  required bool esAdmin,
  required bool chatHabilitado,
}) async {
  if (kIsWeb) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alias_usuario', alias);
    await prefs.setBool('es_admin', esAdmin);
    await prefs.setBool('notif_chat_habilitada', chatHabilitado);
  } catch (e) {
    debugPrint('Error guardando prefs suscripción: $e');
  }

  try {
    final fcm = FirebaseMessaging.instance;
    if (esAdmin) {
      await fcm.subscribeToTopic('admin_fulbito');
    } else {
      await fcm.unsubscribeFromTopic('admin_fulbito');
    }

    if (chatHabilitado) {
      await fcm.subscribeToTopic('chat_vestuario');
    } else {
      await fcm.unsubscribeFromTopic('chat_vestuario');
    }
  } catch (e) {
    debugPrint('Error al configurar suscripciones FCM: $e');
  }
}

Future<String?> _obtenerAccessTokenFcm() async {
  final ahora = DateTime.now().toUtc();
  if (_cachedFcmToken != null &&
      _cachedFcmTokenExpiry != null &&
      ahora.isBefore(_cachedFcmTokenExpiry!.subtract(const Duration(minutes: 2)))) {
    return _cachedFcmToken;
  }

  try {
    if (_cachedServiceAccountJson == null) {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('fcm')
          .get();
      if (!doc.exists || doc.data() == null) return null;

      final data = doc.data()!;
      if (data['serviceAccount'] is Map) {
        _cachedServiceAccountJson =
            Map<String, dynamic>.from(data['serviceAccount'] as Map);
      } else if (data['serviceAccount'] is String) {
        _cachedServiceAccountJson =
            jsonDecode(data['serviceAccount'] as String) as Map<String, dynamic>;
      } else if (data['private_key'] != null && data['client_email'] != null) {
        _cachedServiceAccountJson = Map<String, dynamic>.from(data);
      }
    }

    if (_cachedServiceAccountJson == null) return null;

    final client = http.Client();
    try {
      final creds = await obtenerCredencialesFcm(
        _cachedServiceAccountJson!,
        client,
      );
      if (creds == null) return null;
      _cachedFcmToken = creds['token'] as String?;
      _cachedFcmTokenExpiry = creds['expiry'] as DateTime?;
      return _cachedFcmToken;
    } finally {
      client.close();
    }

  } catch (e) {
    debugPrint('Error al obtener token FCM: $e');
    return null;
  }
}

Future<void> enviarPushNotificacion({
  required String topic,
  required Map<String, String> data,
}) async {
  try {
    final token = await _obtenerAccessTokenFcm();
    if (token == null || token.isEmpty) return;

    final projectId =
        (_cachedServiceAccountJson?['project_id'] ?? 'fulbito-svfc').toString();

    final response = await http.post(
      Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'message': {
          'topic': topic,
          'data': data,
          'android': {
            'priority': 'HIGH',
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      debugPrint('FCM HTTP ${response.statusCode}: ${response.body}');
    }
  } catch (e) {
    debugPrint('Error al enviar push FCM: $e');
  }
}

Future<void> mostrarNotificacion({
  required int id,
  required String titulo,
  required String cuerpo,
  String canalId = 'fulbito_notif_channel',
  String canalNombre = 'Avisos de Partidos',
}) async {
  if (kIsWeb) return;

  try {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      canalId,
      canalNombre,
      channelDescription:
          'Notificaciones sobre convocatorias y estado del equipo',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(cuerpo),
    );

    final NotificationDetails details = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      id,
      titulo,
      cuerpo,
      details,
    );
  } catch (e) {
    debugPrint('Error al mostrar notificación local: $e');
  }
}

Future<void> programarRecordatorioAsistencia({
  required DateTime fechaHora,
  required String partidoTexto,
}) async {
  if (kIsWeb) return;

  _configurarZonaHorariaLocal();

  DateTime objetivo = fechaHora;
  final ahora = DateTime.now();
  while (!objetivo.isAfter(ahora)) {
    objetivo = objetivo.add(const Duration(days: 7));
  }

  try {
    final tzFecha = tz.TZDateTime.from(objetivo, tz.local);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'fulbito_recordatorios_channel',
        'Recordatorios Programados',
        channelDescription: 'Recordatorio semanal para confirmar asistencia',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        900,
        '⚽ Recordatorio de Asistencia Fulbito',
        'Recordá confirmar si jugás el $partidoTexto.',
        tzFecha,
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Fallback a alarma inexacta: $e');
      await flutterLocalNotificationsPlugin.zonedSchedule(
        900,
        '⚽ Recordatorio de Asistencia Fulbito',
        'Recordá confirmar si jugás el $partidoTexto.',
        tzFecha,
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  } catch (e2) {
    debugPrint('Error al programar recordatorio: $e2');
  }
}
