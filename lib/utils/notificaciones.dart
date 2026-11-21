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
StreamSubscription<RemoteMessage>? _onMessageSub;

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
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          'fulbito_cumpleanos_channel',
          'Cumpleaños del Plantel',
          description: 'Avisos de cumpleaños de los jugadores',
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

    await _onMessageSub?.cancel();
    _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
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
    // IMPORTANTE: recargar desde disco para sincronizar entre isolate background y foreground
    await prefs.reload();
    final lista = prefs.getStringList('notifs_mostradas_ids') ?? [];
    final idStr = '$id';
    if (lista.contains(idStr)) return false;

    lista.add(idStr);
    if (lista.length > 120) {
      lista.removeRange(0, lista.length - 120);
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
    await prefs.reload();
    final String miAlias = prefs.getString('alias_usuario') ?? '';
    final String tipo = (data['tipo'] ?? '').toString();
    final int notifId = int.tryParse((data['notifId'] ?? '').toString()) ??
        (DateTime.now().millisecondsSinceEpoch % 100000000);

    // Ignorar mensajes viejos (más de 15 minutos) que Android entregue tarde al encender/abrir
    final int tsMensaje = int.tryParse((data['ts'] ?? '').toString()) ?? 0;
    if (tsMensaje > 0) {
      final int diffMs = DateTime.now().millisecondsSinceEpoch - tsMensaje;
      if (diffMs > 15 * 60 * 1000) {
        return;
      }
    }

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
    } else if (tipo == 'cumpleanos') {
      final String mensajeCumple = (data['mensaje'] ?? '').toString();
      if (mensajeCumple.isEmpty) return;

      final esNueva = await marcarNotificacionComoMostrada(notifId);
      if (!esNueva) return;

      await mostrarNotificacion(
        id: notifId,
        titulo: '🎂 ¡Cumpleaños en el plantel!',
        cuerpo: mensajeCumple,
        canalId: 'fulbito_cumpleanos_channel',
        canalNombre: 'Cumpleaños del Plantel',
      );
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
    // Topic global para todos los usuarios de la app (cumpleaños, avisos generales)
    await fcm.subscribeToTopic('todos_fulbito');

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

    final payloadData = Map<String, String>.from(data);
    payloadData.putIfAbsent(
        'ts', () => '${DateTime.now().millisecondsSinceEpoch}');

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
          'data': payloadData,
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

/// Programa alarmas locales a las 10:00 AM para el próximo cumpleaños de cada jugador
/// y dispara el push global a las 10:00 AM en adelante si hoy cumple alguien y aún no se avisó.
Future<void> sincronizarNotificacionesCumpleanos(List<Jugador> plantel) async {
  if (kIsWeb) return;

  _configurarZonaHorariaLocal();
  final ahora = DateTime.now();

  // Cancelar alarmas previas de cumpleaños (rango 2000..2150)
  for (int id = 2000; id < 2150; id++) {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (_) {}
  }

  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'fulbito_cumpleanos_channel',
      'Cumpleaños del Plantel',
      channelDescription: 'Avisos de cumpleaños de los jugadores',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );

  int idx = 0;
  for (final j in plantel) {
    final nac = j.fechaNacimientoDateTime;
    if (nac == null || j.nombre.trim().isEmpty) continue;

    // 1. Verificar si HOY es su cumpleaños y ya son las 10:00 AM o más
    if (nac.month == ahora.month && nac.day == ahora.day && ahora.hour >= 10) {
      final int edad = ahora.year - nac.year;
      final String claveDoc = '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}_${normalizar(j.nombre)}';
      final String mensaje = 'Hoy ${j.nombre.trim()} cumple $edad años!';

      try {
        final ref = FirebaseFirestore.instance.collection('cumpleanos_enviados').doc(claveDoc);
        bool debeEnviar = false;
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (!snap.exists) {
            tx.set(ref, {
              'jugador': j.nombre.trim(),
              'edad': edad,
              'enviadoEn': FieldValue.serverTimestamp(),
            });
            debeEnviar = true;
          }
        });

        if (debeEnviar) {
          final int notifId = 300000 + (claveDoc.hashCode.abs() % 500000);
          await enviarPushNotificacion(
            topic: 'todos_fulbito',
            data: {
              'tipo': 'cumpleanos',
              'mensaje': mensaje,
              'notifId': '$notifId',
            },
          );
        }
      } catch (e) {
        debugPrint('Error al verificar envío push cumpleaños: $e');
      }
    }

    // 2. Programar alarma local a las 10:00 AM para el próximo cumpleaños
    if (idx < 150) {
      int anioObjetivo = ahora.year;
      DateTime proximoCumple = DateTime(anioObjetivo, nac.month, nac.day, 10, 0, 0);
      if (!proximoCumple.isAfter(ahora)) {
        anioObjetivo += 1;
        proximoCumple = DateTime(anioObjetivo, nac.month, nac.day, 10, 0, 0);
      }

      final int edadQueCumple = anioObjetivo - nac.year;
      final String cuerpoLocal = 'Hoy ${j.nombre.trim()} cumple $edadQueCumple años!';
      final int alarmId = 2000 + idx;

      try {
        final tzFecha = tz.TZDateTime.from(proximoCumple, tz.local);
        await flutterLocalNotificationsPlugin.zonedSchedule(
          alarmId,
          '🎂 ¡Cumpleaños en el plantel!',
          cuerpoLocal,
          tzFecha,
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (_) {
        try {
          final tzFecha = tz.TZDateTime.from(proximoCumple, tz.local);
          await flutterLocalNotificationsPlugin.zonedSchedule(
            alarmId,
            '🎂 ¡Cumpleaños en el plantel!',
            cuerpoLocal,
            tzFecha,
            details,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        } catch (e2) {
          debugPrint('Error programando alarma local cumpleaños: $e2');
        }
      }
      idx++;
    }
  }
}
