import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ============================================================================
// CONFIGURACIÓN DE ACCESOS, GITHUB Y VERSIÓN UNIFICADA
// ============================================================================
String gAppVersion = '1.0.10';
const String kGitHubUser = 'DemianGodOk';
const String kGitHubRepo = 'Fulbito';

const bool kBypassLogin = false;
const String kSuperAdminEmail = 'demian.soriano@gmail.com';

// ============================================================================
// SERVICIO DE NOTIFICACIONES LOCALES
// ============================================================================
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> inicializarNotificaciones() async {
  if (kIsWeb) return;
  tz.initializeTimeZones();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
  );

  final androidImpl = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
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
    channelDescription: 'Notificaciones sobre convocatorias y estado del equipo',
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
    debugPrint("Error al programar recordatorio: $e");
  }
}

// ============================================================================
// MODELOS Y UTILIDADES
// ============================================================================
class Jugador {
  String nombre;
  String email;
  String uid;
  bool esModerador;

  Jugador({
    required this.nombre,
    this.email = '',
    this.uid = '',
    this.esModerador = false,
  });

  Map<String, dynamic> toMap() => {
    'nombre': nombre,
    'email': email,
    'uid': uid,
    'esModerador': esModerador,
  };

  factory Jugador.fromMap(Map<String, dynamic> map) => Jugador(
    nombre: map['nombre'] ?? '',
    email: map['email'] ?? '',
    uid: map['uid'] ?? '',
    esModerador: map['esModerador'] ?? false,
  );
}

String limpiarNombre(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final limpio = raw.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  if (limpio.toLowerCase() == 'jugador s.v.f.c.') return '';
  return limpio;
}

String _normalizar(String s) {
  var res = limpiarNombre(s).trim().toLowerCase();
  res = res
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');
  return res;
}

bool sonElMismoJugador(String nombreA, String nombreB) {
  final a = _normalizar(nombreA);
  final b = _normalizar(nombreB);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;

  final esMaxiCA = a == 'maxi c' || a.contains('maxi c');
  final esMaxiCB = b == 'maxi c' || b.contains('maxi c');
  if (esMaxiCA != esMaxiCB) return false;

  final esDemianA = a.contains('demian') || a.contains('demio');
  final esDemianB = b.contains('demian') || b.contains('demio');
  if (esDemianA && esDemianB) return true;

  final primA = a.split(RegExp(r'\s+')).first;
  final primB = b.split(RegExp(r'\s+')).first;
  if (primA == b || primB == a) return true;
  if (primA == primB && primA.length > 2 && primA != 'maxi') return true;

  return false;
}

String formatearFechaEspanol(DateTime date) {
  const dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  const meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
  ];
  return '${dias[date.weekday - 1]} ${date.day} de ${meses[date.month - 1]}';
}

DateTime? _parsearFechaEspanol(String texto) {
  try {
    final match = RegExp(r'(\d+)\s+de\s+(\w+)', caseSensitive: false).firstMatch(texto);
    if (match != null) {
      final dia = int.tryParse(match.group(1)!) ?? 1;
      final mesNombre = match.group(2)!.toLowerCase();
      const meses = [
        'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
        'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
      ];
      final mesIdx = meses.indexOf(mesNombre);
      if (mesIdx != -1) {
        final anioActual = DateTime.now().year;
        return DateTime(anioActual, mesIdx + 1, dia);
      }
    }
  } catch (_) {}
  return null;
}

String formatearHora(TimeOfDay time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m hs';
}

String resolverAliasOPrimerNombre({
  required String nombreGoogle,
  required String emailGoogle,
  required String? uidGoogle,
  required List<Jugador> plantel,
}) {
  final emailLimpio = emailGoogle.toLowerCase().trim();
  final uidLimpio = uidGoogle?.trim() ?? '';

  // 1. Alias asignado en el plantel de Firestore (coincidencia por correo o UID)
  for (var j in plantel) {
    final jEmail = j.email.toLowerCase().trim();
    final jUid = j.uid.trim();
    final matchEmail = jEmail.isNotEmpty && jEmail == emailLimpio;
    final matchUid = jUid.isNotEmpty && uidLimpio.isNotEmpty && jUid == uidLimpio;
    if (matchEmail || matchUid) {
      if (j.nombre.trim().isNotEmpty) {
        return j.nombre.trim();
      }
    }
  }

  for (var j in plantel) {
    if (j.nombre.trim().isNotEmpty && sonElMismoJugador(j.nombre, nombreGoogle)) {
      return j.nombre.trim();
    }
  }

  // 2. Únicamente el primer nombre de la cuenta de Google
  final limpio = limpiarNombre(nombreGoogle);
  if (limpio.isNotEmpty) {
    final primer = limpio.split(RegExp(r'\s+')).first.trim();
    if (primer.isNotEmpty) {
      return primer;
    }
  }

  // 3. Prefijo del correo antes del @ con primera letra mayúscula
  if (emailLimpio.isNotEmpty && emailLimpio.contains('@')) {
    final pre = emailLimpio.split('@').first.trim();
    if (pre.isNotEmpty) {
      return pre[0].toUpperCase() + (pre.length > 1 ? pre.substring(1).toLowerCase() : '');
    }
  }

  return 'Jugador';
}

bool _esVersionMayor(String nueva, String actual) {
  List<int> vNueva = nueva.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  List<int> vActual = actual.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  for (int i = 0; i < 3; i++) {
    int n = i < vNueva.length ? vNueva[i] : 0;
    int a = i < vActual.length ? vActual[i] : 0;
    if (n > a) return true;
    if (n < a) return false;
  }
  return false;
}

// ============================================================================
// VERIFICACIÓN Y ACTUALIZACIÓN OTA NATIVA
// ============================================================================
Future<void> verificarActualizacionGitHub(BuildContext context) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  if (kGitHubUser == 'TU_USUARIO_GITHUB') return;

  try {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/$kGitHubUser/$kGitHubRepo/releases/latest'),
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'FulbitoApp'
      },
    );

    if (response.statusCode != 200) return;

    final data = jsonDecode(response.body);
    final String versionRemota =
        (data['tag_name'] ?? '').toString().replaceAll(RegExp(r'^[vV]'), '').trim();

    if (_esVersionMayor(versionRemota, gAppVersion) && context.mounted) {
      String urlDescarga = '';
      final List assets = data['assets'] ?? [];
      for (var asset in assets) {
        final String nombreArchivo = asset['name']?.toString().toLowerCase() ?? '';
        if (nombreArchivo.endsWith('.apk')) {
          urlDescarga = asset['browser_download_url'] ?? '';
          break;
        }
      }

      if (urlDescarga.isNotEmpty) {
        _mostrarDialogoDescargaEInstalacion(context, versionRemota, gAppVersion, urlDescarga);
      }
    }
  } catch (e) {
    debugPrint("Error al verificar actualización en GitHub: $e");
  }
}

void _mostrarDialogoDescargaEInstalacion(
  BuildContext context,
  String versionRemota,
  String versionActual,
  String urlDescarga,
) {
  bool descargando = false;
  double progreso = 0.0;
  String estadoTexto = '';
  String? errorTexto;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        void iniciarDescarga() {
          setDialogState(() {
            descargando = true;
            progreso = 0.0;
            estadoTexto = 'Iniciando descarga...';
            errorTexto = null;
          });

          try {
            OtaUpdate()
                .execute(urlDescarga, destinationFilename: 'fulbito.apk')
                .listen(
              (OtaEvent event) {
                setDialogState(() {
                  switch (event.status) {
                    case OtaStatus.DOWNLOADING:
                      final valor = double.tryParse(event.value ?? '0') ?? 0.0;
                      progreso = (valor / 100.0).clamp(0.0, 1.0);
                      estadoTexto = 'Descargando: ${event.value}%';
                      break;
                    case OtaStatus.INSTALLING:
                      progreso = 1.0;
                      estadoTexto = 'Descarga completa. Abriendo instalador...';
                      break;
                    case OtaStatus.ALREADY_RUNNING_ERROR:
                      errorTexto = 'Ya hay una descarga en proceso.';
                      descargando = false;
                      break;
                    case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                      errorTexto =
                          'Permiso denegado. Habilitá "Instalar aplicaciones desconocidas" en los ajustes de Fulbito.';
                      descargando = false;
                      break;
                    default:
                      errorTexto = 'No se pudo completar la descarga (${event.status}).';
                      descargando = false;
                      break;
                  }
                });
              },
              onError: (e) {
                setDialogState(() {
                  errorTexto = 'Error al descargar: $e';
                  descargando = false;
                });
              },
            );
          } catch (e) {
            setDialogState(() {
              errorTexto = 'Fallo al iniciar el instalador: $e';
              descargando = false;
            });
          }
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.system_update, color: Colors.tealAccent),
              SizedBox(width: 8),
              Text('Actualización disponible', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!descargando) ...[
                Text(
                  'Hay una nueva versión ($versionRemota) de Fulbito.\nTu versión instalada: $versionActual.\n\n¿Deseás descargar e instalar la actualización ahora?',
                  style: const TextStyle(height: 1.4),
                ),
                if (errorTexto != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: Text(
                      errorTexto!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                ],
              ] else ...[
                Text(
                  'Descargando versión $versionRemota...',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progreso > 0 ? progreso : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                ),
                const SizedBox(height: 12),
                Text(
                  estadoTexto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.tealAccent),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Al finalizar, el sistema abrirá la ventana para confirmar la actualización.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ],
          ),
          actions: [
            if (!descargando) ...[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Más tarde', style: TextStyle(color: Colors.grey)),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.download, size: 18),
                onPressed: iniciarDescarga,
                label: const Text('Actualizar ahora'),
              ),
            ],
          ],
        );
      },
    ),
  );
}

// ============================================================================
// MAIN Y ARRANQUE
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) {
      gAppVersion = info.version;
    }
  } catch (_) {}

  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyBcalfFCa9fKb-VnY0hQFd9ehTr51I2lk8",
          authDomain: "fulbito-svfc.firebaseapp.com",
          projectId: "fulbito-svfc",
          storageBucket: "fulbito-svfc.firebasestorage.app",
          messagingSenderId: "112754897657",
          appId: "1:112754897657:web:a52806ee7db2c045322828",
        ),
      );
    } else {
      await Firebase.initializeApp();
      await inicializarNotificaciones();
    }
  } catch (e) {
    debugPrint("Error al inicializar Firebase: $e");
  }

  runApp(const FulbitoApp());
}

class FulbitoApp extends StatelessWidget {
  const FulbitoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fulbito',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF142946),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Control de sesión
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _cargando = false;

  Future<void> _iniciarSesionGoogle() async {
    setState(() => _cargando = true);
    try {
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');

      UserCredential cred;
      if (kIsWeb) {
        cred = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else {
        cred = await FirebaseAuth.instance.signInWithProvider(googleProvider);
      }

      final user = cred.user;
      if (user != null) {
        String nombreGuardar = limpiarNombre(user.displayName);
        if (nombreGuardar.isEmpty && user.email != null && user.email!.contains('@')) {
          final pre = user.email!.split('@').first.trim();
          nombreGuardar = pre[0].toUpperCase() + (pre.length > 1 ? pre.substring(1).toLowerCase() : '');
        }

        await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set({
          'uid': user.uid,
          'nombre': nombreGuardar.isNotEmpty ? nombreGuardar : 'Jugador',
          'email': user.email ?? '',
          'fotoUrl': user.photoURL,
          'ultimoAcceso': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al iniciar sesión: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cerrarSesion() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (kBypassLogin) {
      return PantallaPrincipal(
        nombreJugador: 'Demian Soriano',
        emailJugador: kSuperAdminEmail,
        fotoUrl: null,
        onCerrarSesion: () {},
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (_cargando || snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;
        if (user == null) {
          return LoginScreen(onLogin: _iniciarSesionGoogle);
        }

        return PantallaPrincipal(
          nombreJugador: limpiarNombre(user.displayName),
          emailJugador: user.email ?? '',
          fotoUrl: user.photoURL,
          onCerrarSesion: _cerrarSesion,
        );
      },
    );
  }
}

/// Login
class LoginScreen extends StatelessWidget {
  final VoidCallback onLogin;
  const LoginScreen({super.key, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset('assets/logo.jpg', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Fulbito',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2.0),
              ),
              const SizedBox(height: 8),
              Text(
                'S.V.F.C. - Gestión de partidos, rotación y vestuario.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey[400], height: 1.4),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: onLogin,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey.shade700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.white10,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.g_mobiledata, size: 30, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Continuar con Google',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Versión $gAppVersion',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// VESTUARIO (CHAT TEMPORAL 24 HORAS EN DOCUMENTO ÚNICO)
// ============================================================================
class VestuarioScreen extends StatefulWidget {
  final String aliasUsuario;
  const VestuarioScreen({super.key, required this.aliasUsuario});

  @override
  State<VestuarioScreen> createState() => _VestuarioScreenState();
}

class _VestuarioScreenState extends State<VestuarioScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _enviando = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _enviarMensaje() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    _ctrl.clear();

    try {
      final ahora = DateTime.now().millisecondsSinceEpoch;
      final limite24hs = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;

      final docRef = FirebaseFirestore.instance.collection('partidos').doc('actual_chat');
      final doc = await docRef.get();
      final List<dynamic> actuales = doc.exists ? (doc.data()?['mensajes'] as List<dynamic>? ?? []) : [];

      List> filtrados = [];
      for (var m in actuales) {
        if (m is Map) {
          final ts = m['ts'];
          if (ts is int && ts > limite24hs) {
            filtrados.add(Map<String, dynamic>.from(m));
          }
        }
      }

      filtrados.add({
        'autor': widget.aliasUsuario,
        'texto': txt,
        'ts': ahora,
      });

      if (filtrados.length > 40) {
        filtrados = filtrados.sublist(filtrados.length - 40);
      }

      await docRef.set({
        'mensajes': filtrados,
      }, SetOptions(merge: true));

      _scrollHaciaAbajo();
    } catch (e) {
      debugPrint("Error al enviar mensaje en vestuario: $e");
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _scrollHaciaAbajo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF16253B),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.forum_outlined, color: Colors.tealAccent, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vestuario',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'Los mensajes se borran solos a las 24 horas (máx. 40).',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('partidos').doc('actual_chat').snapshots(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snap.data?.data() as Map<String, dynamic>? ?? {};
              final limite24hs = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
              final rawMensajes = (data['mensajes'] as List<dynamic>? ?? []);

              final List> mensajes = [];
              for (var m in rawMensajes) {
                if (m is Map) {
                  final ts = m['ts'];
                  if (ts is int && ts > limite24hs) {
                    mensajes.add(Map<String, dynamic>.from(m));
                  }
                }
              }

              if (mensajes.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mark_chat_unread_outlined, size: 48, color: Colors.grey.shade600),
                        const SizedBox(height: 12),
                        const Text(
                          'El vestuario está tranquilo',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'No hay mensajes en las últimas 24 horas.\n¡Escribí el primero para encender la charla!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });

              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                itemCount: mensajes.length,
                itemBuilder: (c, i) {
                  final m = mensajes[i];
                  final autor = m['autor']?.toString() ?? 'Jugador';
                  final texto = m['texto']?.toString() ?? '';
                  final ts = m['ts'] as int?;
                  final esMio = sonElMismoJugador(autor, widget.aliasUsuario);

                  String horaFormateada = '';
                  if (ts != null) {
                    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
                    horaFormateada = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                  }

                  return Align(
                    alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                      decoration: BoxDecoration(
                        color: esMio ? const Color(0xFF0F5132) : const Color(0xFF16253B),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(14),
                          topRight: const Radius.circular(14),
                          bottomLeft: Radius.circular(esMio ? 14 : 2),
                          bottomRight: Radius.circular(esMio ? 2 : 14),
                        ),
                        border: Border.all(
                          color: esMio ? Colors.tealAccent.withValues(alpha: 0.3) : Colors.white10,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!esMio)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                autor,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.tealAccent,
                                ),
                              ),
                            ),
                          Text(
                            texto,
                            style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.3),
                          ),
                          if (horaFormateada.isNotEmpty)
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  horaFormateada,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: esMio ? Colors.tealAccent.withValues(alpha: 0.7) : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF101C2B),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _enviarMensaje(),
                    decoration: InputDecoration(
                      hintText: 'Mensaje al vestuario...',
                      hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                  ),
                  icon: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.send, size: 18),
                  onPressed: _enviando ? null : _enviarMensaje,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// PANTALLA PRINCIPAL
// ============================================================================
class PantallaPrincipal extends StatefulWidget {
  final String nombreJugador;
  final String emailJugador;
  final String? fotoUrl;
  final VoidCallback onCerrarSesion;

  const PantallaPrincipal({
    super.key,
    required this.nombreJugador,
    required this.emailJugador,
    this.fotoUrl,
    required this.onCerrarSesion,
  });

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  int _indiceActual = 0;
  String? _ultimoRecordatorioProgramado;
  bool _verificandoSemana = false;
  DateTime? _ultimaAlertaNotificada;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      verificarActualizacionGitHub(context);
    });
  }

  bool get _esAdmin =>
      kBypassLogin || widget.emailJugador.toLowerCase().trim() == kSuperAdminEmail.toLowerCase().trim();

  String? get _fotoUrlConProxy {
    if (widget.fotoUrl == null || widget.fotoUrl!.isEmpty) return null;
    return 'https://images.weserv.nl/?url=${Uri.encodeComponent(widget.fotoUrl!)}';
  }

  void _revisarProgramacionRecordatorio(Map<String, dynamic> datosPartido) {
    final int? millis = datosPartido['recordatorioMillis'];
    final String partidoTexto = "${datosPartido['dia'] ?? ''} a las ${datosPartido['hora'] ?? ''}".trim();

    if (millis != null) {
      final key = '$millis-$partidoTexto';
      if (_ultimoRecordatorioProgramado != key) {
        _ultimoRecordatorioProgramado = key;
        final dt = DateTime.fromMillisecondsSinceEpoch(millis);
        programarRecordatorioAsistencia(fechaHora: dt, partidoTexto: partidoTexto);
      }
    }
  }

  void _verificarYActualizarSemanaPartido(Map<String, dynamic> datosPartido) async {
    if (_verificandoSemana) return;

    DateTime? fechaPartido;
    if (datosPartido['fechaMillis'] != null) {
      fechaPartido = DateTime.fromMillisecondsSinceEpoch(datosPartido['fechaMillis'] as int);
    } else if (datosPartido['dia'] != null) {
      fechaPartido = _parsearFechaEspanol(datosPartido['dia'].toString());
    }

    if (fechaPartido == null) return;

    final limiteExpiracion = DateTime(fechaPartido.year, fechaPartido.month, fechaPartido.day + 1);

    if (DateTime.now().isAfter(limiteExpiracion)) {
      _verificandoSemana = true;
      try {
        DateTime nuevaFecha = fechaPartido.add(const Duration(days: 7));
        while (DateTime(nuevaFecha.year, nuevaFecha.month, nuevaFecha.day + 1).isBefore(DateTime.now())) {
          nuevaFecha = nuevaFecha.add(const Duration(days: 7));
        }

        final nuevoDiaTexto = formatearFechaEspanol(nuevaFecha);

        await FirebaseFirestore.instance.collection('partidos').doc('actual').set({
          'dia': nuevoDiaTexto,
          'fechaMillis': nuevaFecha.millisecondsSinceEpoch,
          'asistencia': FieldValue.delete(),
          'ultimaAlerta': FieldValue.delete(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error al actualizar fecha semanal del partido: $e');
      } finally {
        _verificandoSemana = false;
      }
    }
  }

  void _confirmarResetConvocatoria(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.restart_alt, color: Colors.amberAccent),
            SizedBox(width: 8),
            Text('Resetear Convocatoria', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: const Text(
          'Esta acción borrará todas las confirmaciones y bajas actuales. Todos los jugadores volverán a quedar "Sin responder".\n\n¿Deseás continuar?',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade900),
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.collection('partidos').doc('actual').update({
                'asistencia': FieldValue.delete(),
                'ultimaAlerta': FieldValue.delete(),
              });
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Convocatoria reseteada con éxito.'),
                    backgroundColor: Colors.teal,
                  ),
                );
              }
            },
            child: const Text('Resetear'),
          ),
        ],
      ),
    );
  }

  void _abrirGestionPlantel(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (ctx) => const GestionPlantelScreen()),
    );
  }

  void _mostrarDialogoConfiguracion(BuildContext context, Map<String, dynamic> datosActuales) {
    final diaCtrl = TextEditingController(text: datosActuales['dia'] ?? 'Viernes 30 de Octubre');
    final horaCtrl = TextEditingController(text: datosActuales['hora'] ?? '20:00 hs');
    final lugarCtrl = TextEditingController(text: datosActuales['lugar'] ?? 'Estación 98 - Cancha 2');
    final cupoCtrl = TextEditingController(text: '${datosActuales['cupoMaximo'] ?? 10}');

    final recDiaCtrl = TextEditingController(text: datosActuales['recordatorioDia'] ?? 'Jueves anterior');
    final recHoraCtrl = TextEditingController(text: datosActuales['recordatorioHora'] ?? '10:00 hs');

    DateTime fechaPartidoSeleccionada = datosActuales['fechaMillis'] != null
        ? DateTime.fromMillisecondsSinceEpoch(datosActuales['fechaMillis'])
        : (_parsearFechaEspanol(datosActuales['dia'] ?? '') ?? DateTime.now());

    DateTime fechaRecordatorioSeleccionada = datosActuales['recordatorioMillis'] != null
        ? DateTime.fromMillisecondsSinceEpoch(datosActuales['recordatorioMillis'])
        : DateTime.now().add(const Duration(days: 1));
    TimeOfDay horaRecordatorioSeleccionada = const TimeOfDay(hour: 10, minute: 0);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.lightBlueAccent),
              SizedBox(width: 8),
              Text('Configurar Partido', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: diaCtrl,
                  readOnly: true,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fechaPartidoSeleccionada,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setDlgState(() {
                        fechaPartidoSeleccionada = picked;
                        diaCtrl.text = formatearFechaEspanol(picked);
                      });
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Fecha del Partido',
                    prefixIcon: Icon(Icons.calendar_month, color: Colors.lightBlueAccent, size: 20),
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: horaCtrl,
                  readOnly: true,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: const TimeOfDay(hour: 20, minute: 0),
                    );
                    if (picked != null) horaCtrl.text = formatearHora(picked);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Horario',
                    prefixIcon: Icon(Icons.access_time, color: Colors.lightBlueAccent, size: 20),
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lugarCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Cancha / Dirección', prefixIcon: Icon(Icons.location_on_outlined, size: 20)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cupoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Cupo Total de Jugadores', prefixIcon: Icon(Icons.people_alt_outlined, size: 20)),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const Row(
                  children: [
                    Icon(Icons.alarm, color: Colors.tealAccent, size: 18),
                    SizedBox(width: 8),
                    Text('Recordatorio de Confirmación',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: recDiaCtrl,
                  readOnly: true,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fechaRecordatorioSeleccionada,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setDlgState(() {
                        fechaRecordatorioSeleccionada = picked;
                        recDiaCtrl.text = formatearFechaEspanol(picked);
                      });
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Día del Recordatorio',
                    prefixIcon: Icon(Icons.calendar_today, size: 18),
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: recHoraCtrl,
                  readOnly: true,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: horaRecordatorioSeleccionada,
                    );
                    if (picked != null) {
                      setDlgState(() {
                        horaRecordatorioSeleccionada = picked;
                        recHoraCtrl.text = formatearHora(picked);
                      });
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Hora del Recordatorio',
                    prefixIcon: Icon(Icons.access_time, size: 18),
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
            FilledButton(
              onPressed: () async {
                final cupoInt = int.tryParse(cupoCtrl.text) ?? 10;
                final dtRecordatorio = DateTime(
                  fechaRecordatorioSeleccionada.year,
                  fechaRecordatorioSeleccionada.month,
                  fechaRecordatorioSeleccionada.day,
                  horaRecordatorioSeleccionada.hour,
                  horaRecordatorioSeleccionada.minute,
                );

                await FirebaseFirestore.instance.collection('partidos').doc('actual').set({
                  'dia': diaCtrl.text.trim(),
                  'fechaMillis': fechaPartidoSeleccionada.millisecondsSinceEpoch,
                  'hora': horaCtrl.text.trim(),
                  'lugar': lugarCtrl.text.trim(),
                  'cupoMaximo': cupoInt,
                  'recordatorioDia': recDiaCtrl.text.trim(),
                  'recordatorioHora': recHoraCtrl.text.trim(),
                  'recordatorioMillis': dtRecordatorio.millisecondsSinceEpoch,
                }, SetOptions(merge: true));

                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('partidos').doc('actual').snapshots(),
      builder: (context, snapshotPartido) {
        final infoPartido = (snapshotPartido.data?.data() as Map<String, dynamic>?) ?? {
          'dia': 'Viernes 30 de Octubre',
          'hora': '20:00 hs',
          'lugar': 'Estación 98 - Cancha 2',
          'cupoMaximo': 10,
        };

        _revisarProgramacionRecordatorio(infoPartido);
        _verificarYActualizarSemanaPartido(infoPartido);

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('config').doc('plantel').snapshots(),
          builder: (context, snapshotPlantel) {
            List<Jugador> titulares = [];
            List<Jugador> suplentes = [];

            if (snapshotPlantel.hasData && snapshotPlantel.data!.exists) {
              final data = snapshotPlantel.data!.data() as Map<String, dynamic>?;
              if (data != null) {
                if (data['titulares'] != null) {
                  titulares = (data['titulares'] as List)
                      .map((e) => Jugador.fromMap(Map<String, dynamic>.from(e)))
                      .toList();
                }
                if (data['suplentes'] != null) {
                  suplentes = (data['suplentes'] as List)
                      .map((e) => Jugador.fromMap(Map<String, dynamic>.from(e)))
                      .toList();
                }
              }
            }

            final todos = [...titulares, ...suplentes];
            final String aliasUsuario = resolverAliasOPrimerNombre(
              nombreGoogle: widget.nombreJugador,
              emailGoogle: widget.emailJugador,
              uidGoogle: FirebaseAuth.instance.currentUser?.uid,
              plantel: todos,
            );

            // Notificación de baja para administradores
            if (_esAdmin && infoPartido['ultimaAlerta'] != null) {
              final alerta = infoPartido['ultimaAlerta'];
              final ts = (alerta['timestamp'] as Timestamp?)?.toDate();
              if (ts != null && (_ultimaAlertaNotificada == null || ts.isAfter(_ultimaAlertaNotificada!))) {
                _ultimaAlertaNotificada = ts;
                if (ts.isAfter(DateTime.now().subtract(const Duration(minutes: 5))) &&
                    !sonElMismoJugador(alerta['nombre'] ?? '', aliasUsuario)) {
                  mostrarNotificacion(
                    id: 101,
                    titulo: '⚠️ Jugador dado de baja',
                    cuerpo: '${alerta['nombre']} avisó que no juega este partido.',
                  );
                }
              }
            }

            final bool esModerador = _esAdmin ||
                todos.any((j) =>
                    j.esModerador &&
                    (j.email.toLowerCase().trim() == widget.emailJugador.toLowerCase().trim() ||
                        sonElMismoJugador(j.nombre, aliasUsuario)));

            final List<Widget> pantallas = [
              ConvocatoriaScreen(
                nombreJugador: aliasUsuario,
                emailJugador: widget.emailJugador,
                infoPartido: infoPartido,
                esAdmin: _esAdmin,
                titulares: titulares,
                suplentes: suplentes,
              ),
              TablaScreen(
                esAdmin: _esAdmin,
                puedeCargarResultado: _esAdmin || esModerador,
                nombreJugador: aliasUsuario,
                titulares: titulares,
              ),
              RotacionScreen(
                esAdmin: _esAdmin,
                titulares: titulares,
                suplentes: suplentes,
                onAbrirGestionPlantel: () => _abrirGestionPlantel(context),
              ),
              VestuarioScreen(
                aliasUsuario: aliasUsuario,
              ),
            ];

            return Scaffold(
              appBar: AppBar(
                leading: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircleAvatar(
                      backgroundColor: Colors.white, backgroundImage: AssetImage('assets/logo.jpg')),
                ),
                title: const Text('Fulbito',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                actions: [
                  PopupMenuButton<String>(
                    icon: CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: ClipOval(
                        child: _fotoUrlConProxy != null
                            ? Image.network(
                                _fotoUrlConProxy!,
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Text(aliasUsuario.isNotEmpty ? aliasUsuario[0].toUpperCase() : 'J'),
                              )
                            : Text(aliasUsuario.isNotEmpty ? aliasUsuario[0].toUpperCase() : 'J'),
                      ),
                    ),
                    onSelected: (value) {
                      if (value == 'plantel') {
                        _abrirGestionPlantel(context);
                      } else if (value == 'settings') {
                        _mostrarDialogoConfiguracion(context, infoPartido);
                      } else if (value == 'reset') {
                        _confirmarResetConvocatoria(context);
                      } else if (value == 'logout') {
                        widget.onCerrarSesion();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        enabled: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(aliasUsuario,
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                const SizedBox(width: 6),
                                if (_esAdmin)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: Colors.amber.shade800, borderRadius: BorderRadius.circular(4)),
                                    child: const Text('ADMIN',
                                        style: TextStyle(
                                            fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                  )
                                else if (esModerador)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: Colors.teal.shade800, borderRadius: BorderRadius.circular(4)),
                                    child: const Text('MODERADOR',
                                        style: TextStyle(
                                            fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ),
                              ],
                            ),
                            Text(widget.emailJugador,
                                style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      if (_esAdmin) ...[
                        const PopupMenuItem(
                          value: 'plantel',
                          child: Row(
                            children: [
                              Icon(Icons.people_alt, size: 18, color: Colors.orangeAccent),
                              SizedBox(width: 8),
                              Text('Gestionar Plantel', style: TextStyle(color: Colors.orangeAccent)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'settings',
                          child: Row(
                            children: [
                              Icon(Icons.settings, size: 18, color: Colors.lightBlueAccent),
                              SizedBox(width: 8),
                              Text('Configurar partido', style: TextStyle(color: Colors.lightBlueAccent)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'reset',
                          child: Row(
                            children: [
                              Icon(Icons.restart_alt, size: 18, color: Colors.amberAccent),
                              SizedBox(width: 8),
                              Text('Resetear convocatoria', style: TextStyle(color: Colors.amberAccent)),
                            ],
                          ),
                        ),
                      ],
                      const PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, size: 18, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text('Cerrar sesión', style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        enabled: false,
                        height: 26,
                        child: Center(
                          child: Text(
                            'Versión $gAppVersion',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: pantallas[_indiceActual],
              bottomNavigationBar: NavigationBar(
                selectedIndex: _indiceActual,
                onDestinationSelected: (int index) => setState(() => _indiceActual = index),
                destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.sports_soccer_outlined),
                      selectedIcon: Icon(Icons.sports_soccer),
                      label: 'Partido'),
                  NavigationDestination(
                      icon: Icon(Icons.leaderboard_outlined),
                      selectedIcon: Icon(Icons.leaderboard),
                      label: 'Tabla'),
                  NavigationDestination(
                      icon: Icon(Icons.sync_alt_outlined),
                      selectedIcon: Icon(Icons.sync_alt),
                      label: 'Rotación'),
                  NavigationDestination(
                      icon: Icon(Icons.forum_outlined),
                      selectedIcon: Icon(Icons.forum),
                      label: 'Vestuario'),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// GESTIÓN DE PLANTEL
// ============================================================================
class GestionPlantelScreen extends StatefulWidget {
  const GestionPlantelScreen({super.key});

  @override
  State<GestionPlantelScreen> createState() => _GestionPlantelScreenState();
}

class _GestionPlantelScreenState extends State<GestionPlantelScreen> {
  List<Jugador> _titulares = [];
  List<Jugador> _suplentes = [];
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final doc = await FirebaseFirestore.instance.collection('config').doc('plantel').get();
    if (doc.exists && doc.data() != null) {
      final data = doc.data()!;
      if (data['titulares'] != null) {
        _titulares = (data['titulares'] as List)
            .map((e) => Jugador.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (data['suplentes'] != null) {
        _suplentes = (data['suplentes'] as List)
            .map((e) => Jugador.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
    }
    setState(() => _cargando = false);
  }

  Future<void> _guardarEnFirestore() async {
    setState(() => _guardando = true);
    await FirebaseFirestore.instance.collection('config').doc('plantel').set({
      'titulares': _titulares.map((j) => j.toMap()).toList(),
      'suplentes': _suplentes.map((j) => j.toMap()).toList(),
    }, SetOptions(merge: true));

    setState(() => _guardando = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plantel guardado con éxito.'), backgroundColor: Colors.teal),
      );
    }
  }

  void _dialogoNuevoJugador() {
    final nombreCtrl = TextEditingController();
    bool esTitular = true;
    bool esMod = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Nuevo Jugador'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre o Apodo', hintText: 'Ej: Nico'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Titular (Rotación)'),
                    selected: esTitular,
                    onSelected: (val) => setDlgState(() => esTitular = true),
                  ),
                  ChoiceChip(
                    label: const Text('Suplente'),
                    selected: !esTitular,
                    onSelected: (val) => setDlgState(() => esTitular = false),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilterChip(
                label: const Text('Rol: Moderador (cargar partidos)'),
                selected: esMod,
                selectedColor: Colors.teal.shade900,
                onSelected: (val) => setDlgState(() => esMod = val),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
            FilledButton(
              onPressed: () {
                final nombre = nombreCtrl.text.trim();
                if (nombre.isNotEmpty) {
                  setState(() {
                    final item = Jugador(nombre: nombre, esModerador: esMod);
                    if (esTitular) {
                      _titulares.add(item);
                    } else {
                      _suplentes.add(item);
                    }
                  });
                  _guardarEnFirestore();
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }

  void _dialogoAsociarCuenta(Jugador jugador) async {
    final snapshot = await FirebaseFirestore.instance.collection('usuarios').get();
    final usuariosRegistrados = snapshot.docs.map((d) => d.data()).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Asociar a "${jugador.nombre}"'),
        content: SizedBox(
          width: double.maxFinite,
          child: usuariosRegistrados.isEmpty
              ? const Text(
                  'Aún no hay usuarios de Google registrados. Se registran automáticamente al iniciar sesión.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: usuariosRegistrados.length,
                  itemBuilder: (context, index) {
                    final u = usuariosRegistrados[index];
                    final String email = u['email'] ?? '';
                    final String nombreGoogle = u['nombre'] ?? '';
                    final esEste = jugador.email == email && email.isNotEmpty;

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: Colors.white10,
                        child: Text(nombreGoogle.isNotEmpty ? nombreGoogle[0].toUpperCase() : 'U'),
                      ),
                      title: Text(nombreGoogle),
                      subtitle: Text(email, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      trailing: esEste ? const Icon(Icons.check_circle, color: Colors.greenAccent) : null,
                      onTap: () {
                        setState(() {
                          jugador.email = email;
                          jugador.uid = u['uid'] ?? '';
                        });
                        _guardarEnFirestore();
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
        ),
        actions: [
          if (jugador.email.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  jugador.email = '';
                  jugador.uid = '';
                });
                _guardarEnFirestore();
                Navigator.pop(ctx);
              },
              child: const Text('Desvincular', style: TextStyle(color: Colors.redAccent)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _buildBotonAccion({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Plantel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          if (_guardando)
            const Center(
                child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
          else
            IconButton(
              icon: const Icon(Icons.save, color: Colors.lightBlueAccent),
              tooltip: 'Guardar Cambios',
              onPressed: _guardarEnFirestore,
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _dialogoNuevoJugador,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightBlueAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Agregar Nuevo Jugador', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Titulares en Rotación (${_titulares.length})',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                      const Text('Arriba = más prioridad', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_titulares.isEmpty)
                    Card(
                      color: Colors.white.withValues(alpha: 0.02),
                      child: const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                            child: Text('No hay titulares cargados. Usá el botón para agregarlos.',
                                style: TextStyle(color: Colors.grey))),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _titulares.length,
                      itemBuilder: (context, index) {
                        final j = _titulares[index];
                        final bool vinculado = j.email.isNotEmpty;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: const Color(0xFF16253B),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            leading: CircleAvatar(
                              radius: 12,
                              backgroundColor: index < 10 ? Colors.green.shade800 : Colors.red.shade900,
                              child: Text('${index + 1}',
                                  style: const TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    j.nombre,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (j.esModerador) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: Colors.teal.shade800, borderRadius: BorderRadius.circular(4)),
                                    child: const Text('MOD',
                                        style: TextStyle(
                                            fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              vinculado ? j.email : 'Sin vincular a Google',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10, color: vinculado ? Colors.greenAccent : Colors.grey),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildBotonAccion(
                                  icon: Icons.sports,
                                  color: j.esModerador ? Colors.tealAccent : Colors.grey.shade600,
                                  tooltip: j.esModerador ? 'Quitar Moderador' : 'Hacer Moderador',
                                  onPressed: () {
                                    setState(() => j.esModerador = !j.esModerador);
                                    _guardarEnFirestore();
                                  },
                                ),
                                _buildBotonAccion(
                                  icon: vinculado ? Icons.link : Icons.link_off,
                                  color: vinculado ? Colors.greenAccent : Colors.orangeAccent,
                                  tooltip: 'Vincular cuenta',
                                  onPressed: () => _dialogoAsociarCuenta(j),
                                ),
                                _buildBotonAccion(
                                  icon: Icons.arrow_downward,
                                  color: Colors.orangeAccent,
                                  tooltip: 'Pasar a Suplente',
                                  onPressed: () {
                                    setState(() {
                                      _titulares.removeAt(index);
                                      _suplentes.add(j);
                                    });
                                    _guardarEnFirestore();
                                  },
                                ),
                                _buildBotonAccion(
                                  icon: Icons.delete_outline,
                                  color: Colors.redAccent,
                                  tooltip: 'Eliminar',
                                  onPressed: () {
                                    setState(() => _titulares.removeAt(index));
                                    _guardarEnFirestore();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                  Text('Suplentes / Reservas (${_suplentes.length})',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                  const SizedBox(height: 6),
                  if (_suplentes.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('No hay suplentes cargados.', style: TextStyle(color: Colors.grey)))
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _suplentes.length,
                      itemBuilder: (context, index) {
                        final j = _suplentes[index];
                        final bool vinculado = j.email.isNotEmpty;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: Colors.white.withValues(alpha: 0.03),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            leading: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.white12,
                              child: Icon(Icons.person, size: 14, color: Colors.grey),
                            ),
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    j.nombre,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (j.esModerador) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: Colors.teal.shade800, borderRadius: BorderRadius.circular(4)),
                                    child: const Text('MOD',
                                        style: TextStyle(
                                            fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              vinculado ? j.email : 'Sin vincular a Google',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10, color: vinculado ? Colors.greenAccent : Colors.grey),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildBotonAccion(
                                  icon: Icons.sports,
                                  color: j.esModerador ? Colors.tealAccent : Colors.grey.shade600,
                                  tooltip: j.esModerador ? 'Quitar Moderador' : 'Hacer Moderador',
                                  onPressed: () {
                                    setState(() => j.esModerador = !j.esModerador);
                                    _guardarEnFirestore();
                                  },
                                ),
                                _buildBotonAccion(
                                  icon: vinculado ? Icons.link : Icons.link_off,
                                  color: vinculado ? Colors.greenAccent : Colors.orangeAccent,
                                  tooltip: 'Vincular cuenta',
                                  onPressed: () => _dialogoAsociarCuenta(j),
                                ),
                                _buildBotonAccion(
                                  icon: Icons.arrow_upward,
                                  color: Colors.greenAccent,
                                  tooltip: 'Promover a Titular',
                                  onPressed: () {
                                    setState(() {
                                      _suplentes.removeAt(index);
                                      _titulares.add(j);
                                    });
                                    _guardarEnFirestore();
                                  },
                                ),
                                _buildBotonAccion(
                                  icon: Icons.delete_outline,
                                  color: Colors.redAccent,
                                  tooltip: 'Eliminar',
                                  onPressed: () {
                                    setState(() => _suplentes.removeAt(index));
                                    _guardarEnFirestore();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

// ============================================================================
// CONVOCATORIA SCREEN
// ============================================================================
class ConvocatoriaScreen extends StatefulWidget {
  final String nombreJugador;
  final String emailJugador;
  final Map<String, dynamic> infoPartido;
  final bool esAdmin;
  final List<Jugador> titulares;
  final List<Jugador> suplentes;

  const ConvocatoriaScreen({
    super.key,
    required this.nombreJugador,
    required this.emailJugador,
    required this.infoPartido,
    required this.esAdmin,
    required this.titulares,
    required this.suplentes,
  });

  @override
  State<ConvocatoriaScreen> createState() => _ConvocatoriaScreenState();
}

class _ConvocatoriaScreenState extends State<ConvocatoriaScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _cambiarEstadoJugador(Jugador j, String nuevoEstado) async {
    await _db.collection('partidos').doc('actual').set({
      'asistencia': {j.nombre: nuevoEstado},
      if (nuevoEstado == 'baja')
        'ultimaAlerta': {
          'tipo': 'baja',
          'nombre': j.nombre,
          'timestamp': FieldValue.serverTimestamp(),
        },
    }, SetOptions(merge: true));
  }

  Widget _buildBotonAdmin(Jugador j, String estadoActual) {
    if (!widget.esAdmin) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (estadoActual != 'confirmado')
          IconButton(
            icon: const Icon(Icons.check_circle, size: 20, color: Colors.greenAccent),
            tooltip: 'Confirmar a ${j.nombre}',
            onPressed: () => _cambiarEstadoJugador(j, 'confirmado'),
          ),
        if (estadoActual != 'baja')
          IconButton(
            icon: const Icon(Icons.cancel, size: 20, color: Colors.redAccent),
            tooltip: 'Dar de baja a ${j.nombre}',
            onPressed: () => _cambiarEstadoJugador(j, 'baja'),
          ),
      ],
    );
  }

  String _obtenerEstadoDeMapa(String nombre, Map<String, dynamic> asistencia) {
    for (var k in asistencia.keys) {
      if (sonElMismoJugador(k, nombre)) {
        return asistencia[k]?.toString() ?? 'pendiente';
      }
    }
    return 'pendiente';
  }

  @override
  Widget build(BuildContext context) {
    final dia = widget.infoPartido['dia'] ?? 'Viernes 30 de Octubre';
    final hora = widget.infoPartido['hora'] ?? '20:00 hs';
    final lugar = widget.infoPartido['lugar'] ?? 'Estación 98 - Cancha 2';
    final int cupoMaximo = widget.infoPartido['cupoMaximo'] ?? 10;
    final Map<String, dynamic> asistencia =
        (widget.infoPartido['asistencia'] as Map<String, dynamic>?) ?? {};

    final List<Jugador> prioritarios = widget.titulares.take(cupoMaximo).toList();
    final List<Jugador> colaEspera = [
      ...widget.titulares.skip(cupoMaximo),
      ...widget.suplentes,
    ];

    final List<Jugador> prioritariosConfirmados = [];
    final List<Jugador> prioritariosPendientes = [];
    final List<Jugador> prioritariosBajas = [];

    for (var j in prioritarios) {
      String estado = _obtenerEstadoDeMapa(j.nombre, asistencia);
      if (estado == 'confirmado') {
        prioritariosConfirmados.add(j);
      } else if (estado == 'baja') {
        prioritariosBajas.add(j);
      } else {
        prioritariosPendientes.add(j);
      }
    }

    int cuposLiberadosParaCola =
        cupoMaximo - prioritariosConfirmados.length - prioritariosPendientes.length;
    if (cuposLiberadosParaCola < 0) cuposLiberadosParaCola = 0;

    final List<Jugador> colaConfirmados = [];
    final List<Jugador> colaPendientes = [];
    final List<Jugador> colaBajas = [];

    for (var j in colaEspera) {
      String estado = _obtenerEstadoDeMapa(j.nombre, asistencia);
      if (estado == 'confirmado') {
        colaConfirmados.add(j);
      } else if (estado == 'baja') {
        colaBajas.add(j);
      } else {
        colaPendientes.add(j);
      }
    }

    final List<Jugador> ascendidosDeCola = colaConfirmados.take(cuposLiberadosParaCola).toList();
    final List<Jugador> enEsperaConfirmados = colaConfirmados.skip(cuposLiberadosParaCola).toList();

    final List<Jugador> titularesConfirmados = [
      ...prioritariosConfirmados,
      ...ascendidosDeCola,
    ];

    final List<Jugador> bajas = [...prioritariosBajas, ...colaBajas];
    final List<Jugador> pendientes = [...prioritariosPendientes, ...colaPendientes];

    final String miEstado = _obtenerEstadoDeMapa(widget.nombreJugador, asistencia);
    final int totalTitulares = titularesConfirmados.length;
    final jugadorActualObj = Jugador(nombre: widget.nombreJugador, email: widget.emailJugador);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.lightBlueAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(dia,
                            style: const TextStyle(
                                color: Colors.lightBlueAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                      Text('Fútbol ${(cupoMaximo / 2).round()}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(hora, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(lugar,
                              style: const TextStyle(color: Colors.grey),
                              overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Cupos confirmados asegurados:', style: TextStyle(fontSize: 13)),
                      Text(
                        '$totalTitulares / $cupoMaximo',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: totalTitulares >= cupoMaximo
                              ? Colors.lightBlueAccent
                              : Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (totalTitulares / cupoMaximo).clamp(0.0, 1.0),
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(totalTitulares >= cupoMaximo
                        ? Colors.lightBlueAccent
                        : Colors.orangeAccent),
                    borderRadius: BorderRadius.circular(10),
                    minHeight: 6,
                  ),
                  if (prioritariosPendientes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Hay ${prioritariosPendientes.length} titular(es) con cupo reservado que todavía no respondieron.',
                      style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.white.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('¿Jugás esta semana?',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _cambiarEstadoJugador(jugadorActualObj, 'confirmado'),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                miEstado == 'confirmado' ? const Color(0xFF1B5E20) : Colors.grey.shade800,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Confirmo'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _cambiarEstadoJugador(jugadorActualObj, 'baja'),
                          style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: miEstado == 'baja' ? Colors.redAccent : Colors.grey.shade700)),
                          icon: Icon(Icons.close,
                              size: 18, color: miEstado == 'baja' ? Colors.redAccent : Colors.grey),
                          label: Text('Me bajo',
                              style: TextStyle(
                                  color: miEstado == 'baja' ? Colors.redAccent : Colors.grey)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Titulares Confirmados ($totalTitulares / $cupoMaximo)',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              const Text('Lugar asegurado', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          if (titularesConfirmados.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Aún no hay jugadores asegurados.', style: TextStyle(color: Colors.grey)),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: titularesConfirmados.length,
              itemBuilder: (context, index) {
                final j = titularesConfirmados[index];
                final esYo = sonElMismoJugador(j.nombre, widget.nombreJugador);

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: esYo
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.03),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: esYo
                        ? BorderSide(color: Theme.of(context).colorScheme.primary)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.green.shade800,
                      child: Text('${index + 1}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                            child: Text(j.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: esYo ? FontWeight.bold : FontWeight.normal))),
                        if (esYo) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.blueAccent, borderRadius: BorderRadius.circular(4)),
                            child: const Text('Tú',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 16),
                            SizedBox(width: 4),
                            Text('Juega',
                                style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        _buildBotonAdmin(j, 'confirmado'),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (enEsperaConfirmados.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('En Espera (Confirmaron)',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                Text('${enEsperaConfirmados.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: enEsperaConfirmados.length,
              itemBuilder: (context, index) {
                final j = enEsperaConfirmados[index];
                final esYo = sonElMismoJugador(j.nombre, widget.nombreJugador);

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.orangeAccent.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.3)),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.orange.shade900,
                      child: Text('${index + 1}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                            child: Text(j.nombre, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (esYo) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.blueAccent, borderRadius: BorderRadius.circular(4)),
                            child: const Text('Tú',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      prioritariosPendientes.isNotEmpty
                          ? 'Esperando respuesta de ${prioritariosPendientes.length} titular(es) con reserva'
                          : 'Esperando que se libere cupo por baja',
                      style: const TextStyle(fontSize: 10, color: Colors.white60),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${index + 1}° en cola',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                        ),
                        _buildBotonAdmin(j, 'confirmado'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          if (pendientes.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Sin Responder / Pendientes',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                Text('${pendientes.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pendientes.length,
              itemBuilder: (context, index) {
                final j = pendientes[index];
                final bool esTitularPrioritario =
                    prioritarios.any((p) => sonElMismoJugador(p.nombre, j.nombre));
                final bool esTitularEnRiesgo = !esTitularPrioritario &&
                    widget.titulares.skip(cupoMaximo).any((t) => sonElMismoJugador(t.nombre, j.nombre));

                String subtitulo;
                Color colorSubtitulo;
                IconData icono;

                if (esTitularPrioritario) {
                  subtitulo = 'Cupo reservado por rotación';
                  colorSubtitulo = Colors.amberAccent;
                  icono = Icons.shield_outlined;
                } else if (esTitularEnRiesgo) {
                  subtitulo = 'Cupo sujeto a disponibilidad por rotación';
                  colorSubtitulo = Colors.orangeAccent;
                  icono = Icons.swap_vert;
                } else {
                  subtitulo = 'Cupo sujeto a disponibilidad por suplencia';
                  colorSubtitulo = Colors.grey;
                  icono = Icons.person_outline;
                }

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  color: Colors.white.withValues(alpha: 0.02),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      icono,
                      size: 18,
                      color: colorSubtitulo,
                    ),
                    title: Text(j.nombre, style: const TextStyle(color: Colors.white70)),
                    subtitle: Text(
                      subtitulo,
                      style: TextStyle(fontSize: 10, color: colorSubtitulo),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Sin responder', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        _buildBotonAdmin(j, 'pendiente'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          if (bajas.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('No juegan (${bajas.length})',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bajas.length,
              itemBuilder: (context, index) {
                final j = bajas[index];
                return Card(
                  color: Colors.white.withValues(alpha: 0.03),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_off_outlined, color: Colors.grey, size: 18),
                    title: Text(j.nombre, style: const TextStyle(color: Colors.grey)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Baja',
                            style: TextStyle(
                                color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                        _buildBotonAdmin(j, 'baja'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ============================================================================
// TABLA SCREEN (PODIO 1, 2 Y 3 EN NARANJA + EQUIPO CELESTE/AMARILLO)
// ============================================================================
class TablaScreen extends StatefulWidget {
  final bool esAdmin;
  final bool puedeCargarResultado;
  final String nombreJugador;
  final List<Jugador> titulares;

  const TablaScreen({
    super.key,
    required this.esAdmin,
    required this.puedeCargarResultado,
    required this.nombreJugador,
    required this.titulares,
  });

  @override
  State<TablaScreen> createState() => _TablaScreenState();
}

class _TablaScreenState extends State<TablaScreen> {
  int _vistaSeleccionada = 0;

  void _mostrarDialogoCargarResultado(BuildContext context) async {
    final snapshotPartido = await FirebaseFirestore.instance.collection('partidos').doc('actual').get();
    final Map<String, dynamic> asistencia =
        (snapshotPartido.data()?['asistencia'] as Map<String, dynamic>?) ?? {};

    List<String> jugadoresDisponibles = asistencia.entries
        .where((e) => e.value == 'confirmado')
        .map((e) => e.key)
        .toList();

    if (jugadoresDisponibles.isEmpty) {
      jugadoresDisponibles = widget.titulares.map((t) => t.nombre).toList();
    }

    if (!context.mounted) return;

    final fechaCtrl = TextEditingController(text: formatearFechaEspanol(DateTime.now()));
    final golesACtrl = TextEditingController(text: '0');
    final golesBCtrl = TextEditingController(text: '0');
    final nombreEquipoACtrl = TextEditingController(text: 'Equipo Celeste');
    final nombreEquipoBCtrl = TextEditingController(text: 'Equipo Amarillo');

    final Map<String, int> asignaciones = {
      for (var j in jugadoresDisponibles) j: 0,
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF142030),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final equipoA = asignaciones.entries.where((e) => e.value == 1).map((e) => e.key).toList();
          final equipoB = asignaciones.entries.where((e) => e.value == 2).map((e) => e.key).toList();

          return Padding(
            padding: EdgeInsets.only(
                top: 20, left: 20, right: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.sports_score, color: Colors.lightBlueAccent),
                          SizedBox(width: 8),
                          Text('Cargar Resultado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fechaCtrl,
                    readOnly: true,
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2035));
                      if (picked != null) setModalState(() => fechaCtrl.text = formatearFechaEspanol(picked));
                    },
                    decoration: const InputDecoration(
                        labelText: 'Fecha del Partido',
                        prefixIcon: Icon(Icons.calendar_month, color: Colors.lightBlueAccent, size: 20),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                        isDense: true),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                                controller: nombreEquipoACtrl,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none)),
                            TextField(
                                controller: golesACtrl,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.bold, color: Colors.lightBlueAccent),
                                decoration: const InputDecoration(
                                    hintText: '0', border: OutlineInputBorder(), isDense: true)),
                            const SizedBox(height: 4),
                            Text('${equipoA.length} jugadores',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text('VS',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey))),
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                                controller: nombreEquipoBCtrl,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                decoration: const InputDecoration(isDense: true, border: InputBorder.none)),
                            TextField(
                                controller: golesBCtrl,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
                                decoration: const InputDecoration(
                                    hintText: '0', border: OutlineInputBorder(), isDense: true)),
                            const SizedBox(height: 4),
                            Text('${equipoB.length} jugadores',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Asignar Equipos (Blanco ➔ Negro ➔ Quitar)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: jugadoresDisponibles.map((jugador) {
                      final estado = asignaciones[jugador] ?? 0;
                      Color bg = Colors.white10;
                      Color text = Colors.white70;
                      IconData icon = Icons.add;

                      if (estado == 1) {
                        bg = Colors.lightBlueAccent.withValues(alpha: 0.25);
                        text = Colors.lightBlueAccent;
                        icon = Icons.check_circle;
                      } else if (estado == 2) {
                        bg = Colors.orangeAccent.withValues(alpha: 0.25);
                        text = Colors.orangeAccent;
                        icon = Icons.check_circle_outline;
                      }

                      return ActionChip(
                        avatar: Icon(icon, size: 14, color: text),
                        label: Text(jugador, style: TextStyle(color: text, fontSize: 12)),
                        backgroundColor: bg,
                        side: BorderSide(color: text.withValues(alpha: 0.4)),
                        onPressed: () {
                          setModalState(() => asignaciones[jugador] = (estado + 1) % 3);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar Partido y Actualizar Rotación'),
                    onPressed: () async {
                      final int golesA = int.tryParse(golesACtrl.text.trim()) ?? 0;
                      final int golesB = int.tryParse(golesBCtrl.text.trim()) ?? 0;

                      if (equipoA.isEmpty || equipoB.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Debes asignar jugadores a ambos equipos.')));
                        return;
                      }

                      await FirebaseFirestore.instance.collection('historial_partidos').add({
                        'fecha': fechaCtrl.text.trim(),
                        'equipoA_nombre': nombreEquipoACtrl.text.trim(),
                        'equipoB_nombre': nombreEquipoBCtrl.text.trim(),
                        'equipoA_goles': golesA,
                        'equipoB_goles': golesB,
                        'equipoA_jugadores': equipoA,
                        'equipoB_jugadores': equipoB,
                        'creadoEn': FieldValue.serverTimestamp(),
                      });

                      final jugaronSet = {...equipoA, ...equipoB};
                      final noJugaron = widget.titulares
                          .where((j) => !jugaronSet.any((p) => sonElMismoJugador(p, j.nombre)))
                          .toList();
                      final siJugaron = widget.titulares
                          .where((j) => jugaronSet.any((p) => sonElMismoJugador(p, j.nombre)))
                          .toList();
                      final nuevoOrdenTitulares = [...noJugaron, ...siJugaron];

                      await FirebaseFirestore.instance.collection('config').doc('plantel').set({
                        'titulares': nuevoOrdenTitulares.map((j) => j.toMap()).toList(),
                      }, SetOptions(merge: true));

                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('historial_partidos')
          .orderBy('creadoEn', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final Map<String, Map<String, int>> stats = {};

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final int golesA = data['equipoA_goles'] ?? 0;
          final int golesB = data['equipoB_goles'] ?? 0;
          final List eqA = data['equipoA_jugadores'] ?? [];
          final List eqB = data['equipoB_jugadores'] ?? [];

          final bool ganaA = golesA > golesB;
          final bool ganaB = golesB > golesA;
          final bool empate = golesA == golesB;

          void registrar(String jugadorRaw, bool gano, bool empato, bool perdio, int gf, int gc) {
            final l = limpiarNombre(jugadorRaw);
            final jugador = l.isNotEmpty ? l : jugadorRaw.trim();
            if (jugador.isEmpty) return;

            stats.putIfAbsent(jugador, () => {'pj': 0, 'pg': 0, 'pe': 0, 'pp': 0, 'pts': 0, 'gf': 0, 'gc': 0});
            stats[jugador]!['pj'] = stats[jugador]!['pj']! + 1;
            stats[jugador]!['gf'] = stats[jugador]!['gf']! + gf;
            stats[jugador]!['gc'] = stats[jugador]!['gc']! + gc;
            if (gano) {
              stats[jugador]!['pg'] = stats[jugador]!['pg']! + 1;
              stats[jugador]!['pts'] = stats[jugador]!['pts']! + 3;
            } else if (empato) {
              stats[jugador]!['pe'] = stats[jugador]!['pe']! + 1;
              stats[jugador]!['pts'] = stats[jugador]!['pts']! + 1;
            } else if (perdio) {
              stats[jugador]!['pp'] = stats[jugador]!['pp']! + 1;
            }
          }

          for (var j in eqA) {
            registrar(j.toString(), ganaA, empate, ganaB, golesA, golesB);
          }
          for (var j in eqB) {
            registrar(j.toString(), ganaB, empate, ganaA, golesB, golesA);
          }
        }

        final listaRanking = stats.entries.toList()
          ..sort((a, b) {
            final int cmpPts = b.value['pts']!.compareTo(a.value['pts']!);
            if (cmpPts != 0) return cmpPts;
            final int difA = a.value['gf']! - a.value['gc']!;
            final int difB = b.value['gf']! - b.value['gc']!;
            return difB.compareTo(difA);
          });

        return Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                        value: 0,
                        label: Text('Tabla de Posiciones'),
                        icon: Icon(Icons.format_list_numbered)),
                    ButtonSegment(
                        value: 1, label: Text('Partidos Jugados'), icon: Icon(Icons.history)),
                  ],
                  selected: {_vistaSeleccionada},
                  onSelectionChanged: (val) => setState(() => _vistaSeleccionada = val.first),
                ),
                const SizedBox(height: 16),
                if (_vistaSeleccionada == 0) ...[
                  if (listaRanking.isEmpty)
                    Card(
                      color: Colors.white.withValues(alpha: 0.03),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: const Padding(
                        padding: EdgeInsets.all(24.0),
                        child:
                            Center(child: Text('Aún no hay partidos cargados.', style: TextStyle(color: Colors.grey))),
                      ),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                      child: const Row(
                        children: [
                          SizedBox(
                              width: 24,
                              child: Text('#',
                                  style: TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
                          Expanded(
                              child: Text('Jugador',
                                  style: TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
                          SizedBox(
                              width: 28,
                              child: Text('PJ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Colors.grey))),
                          SizedBox(
                              width: 28,
                              child: Text('PG',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Colors.grey))),
                          SizedBox(
                              width: 28,
                              child: Text('PE',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Colors.grey))),
                          SizedBox(
                              width: 28,
                              child: Text('PP',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Colors.grey))),
                          SizedBox(
                              width: 36,
                              child: Text('PTS',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.lightBlueAccent))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: listaRanking.length,
                      itemBuilder: (context, index) {
                        final item = listaRanking[index];
                        final nombre = item.key;
                        final data = item.value;
                        final esYo = sonElMismoJugador(nombre, widget.nombreJugador);

                        final bool esPodio = index == 0 || index == 1 || index == 2;
                        final Color colorNumero = esPodio ? Colors.orangeAccent : Colors.grey;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: esYo
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.03),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: esYo
                                ? BorderSide(color: Theme.of(context).colorScheme.primary)
                                : BorderSide.none,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorNumero,
                                    ),
                                  ),
                                ),
                                Expanded(
                                    child: Text(nombre,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: esYo ? FontWeight.bold : FontWeight.normal))),
                                SizedBox(
                                    width: 28,
                                    child: Text('${data['pj']}',
                                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                                SizedBox(
                                    width: 28,
                                    child: Text('${data['pg']}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 13, color: Colors.tealAccent))),
                                SizedBox(
                                    width: 28,
                                    child: Text('${data['pe']}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 13, color: Colors.grey))),
                                SizedBox(
                                    width: 28,
                                    child: Text('${data['pp']}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 13, color: Colors.redAccent))),
                                SizedBox(
                                    width: 36,
                                    child: Text('${data['pts']}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.lightBlueAccent))),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
                if (_vistaSeleccionada == 1) ...[
                  if (docs.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                            child: Text('No hay partidos en el historial.',
                                style: TextStyle(color: Colors.grey))))
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final docId = docs[index].id;
                        final fecha = data['fecha'] ?? 'Fecha';
                        final eqA = data['equipoA_nombre'] ?? 'Equipo Celeste';
                        final eqB = data['equipoB_nombre'] ?? 'Equipo Amarillo';
                        final int golesA = data['equipoA_goles'] ?? 0;
                        final int golesB = data['equipoB_goles'] ?? 0;
                        final List jugsA = data['equipoA_jugadores'] ?? [];
                        final List jugsB = data['equipoB_jugadores'] ?? [];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          color: const Color(0xFF16253B),
                          child: Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(fecha,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.lightBlueAccent)),
                                    if (widget.esAdmin)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            size: 18, color: Colors.redAccent),
                                        tooltip: 'Borrar partido',
                                        onPressed: () async => await FirebaseFirestore.instance
                                            .collection('historial_partidos')
                                            .doc(docId)
                                            .delete(),
                                      ),
                                  ],
                                ),
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Expanded(
                                        child: Column(children: [
                                      Text(eqA,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold, fontSize: 13)),
                                      const SizedBox(height: 4),
                                      Text('$golesA',
                                          style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.lightBlueAccent))
                                    ])),
                                    const Text('vs', style: TextStyle(fontSize: 16, color: Colors.grey)),
                                    Expanded(
                                        child: Column(children: [
                                      Text(eqB,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold, fontSize: 13)),
                                      const SizedBox(height: 4),
                                      Text('$golesB',
                                          style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orangeAccent))
                                    ])),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        child: Text(
                                            jugsA.map((j) => limpiarNombre(j.toString())).join(', '),
                                            style:
                                                const TextStyle(fontSize: 11, color: Colors.white60),
                                            textAlign: TextAlign.center)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(
                                            jugsB.map((j) => limpiarNombre(j.toString())).join(', '),
                                            style:
                                                const TextStyle(fontSize: 11, color: Colors.white60),
                                            textAlign: TextAlign.center)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
          floatingActionButton: widget.puedeCargarResultado
              ? FloatingActionButton.extended(
                  onPressed: () => _mostrarDialogoCargarResultado(context),
                  backgroundColor: Colors.lightBlueAccent,
                  foregroundColor: Colors.black,
                  icon: const Icon(Icons.add),
                  label: const Text('Cargar Resultado', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              : null,
        );
      },
    );
  }
}

// ============================================================================
// ROTACIÓN SCREEN (LISTA DE ROTACIÓN Y CAMISETAS)
// ============================================================================
class RotacionScreen extends StatelessWidget {
  final bool esAdmin;
  final List<Jugador> titulares;
  final List<Jugador> suplentes;
  final VoidCallback onAbrirGestionPlantel;

  const RotacionScreen({
    super.key,
    required this.esAdmin,
    required this.titulares,
    required this.suplentes,
    required this.onAbrirGestionPlantel,
  });

  void _abrirSelectorCamisetas(BuildContext context, List<String> listaAlfabeticas, String actual) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quién tiene las camisetas?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: listaAlfabeticas.length,
            itemBuilder: (context, index) {
              final nombre = listaAlfabeticas[index];
              final esEl = sonElMismoJugador(nombre, actual);
              return ListTile(
                title: Text(nombre,
                    style: TextStyle(
                        fontWeight: esEl ? FontWeight.bold : FontWeight.normal,
                        color: esEl ? Colors.lightBlueAccent : Colors.white)),
                trailing: esEl ? const Icon(Icons.check, color: Colors.lightBlueAccent) : null,
                onTap: () async {
                  await FirebaseFirestore.instance
                      .collection('config')
                      .doc('camisetas')
                      .set({'lasTiene': nombre}, SetOptions(merge: true));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _abrirEditorCola(BuildContext context) {
    List<Jugador> tempOrden = List.from(titulares);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF142030),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Reordenar Lista de Rotación',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Mantené presionado y arrastrá para cambiar el orden de prioridad.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 380,
                  child: ReorderableListView(
                    onReorderItem: (oldIndex, newIndex) {
                      setModalState(() {
                        final item = tempOrden.removeAt(oldIndex);
                        tempOrden.insert(newIndex, item);
                      });
                    },
                    children: [
                      for (int i = 0; i < tempOrden.length; i++)
                        ListTile(
                          key: ValueKey(tempOrden[i].nombre),
                          dense: true,
                          leading: CircleAvatar(
                            radius: 12,
                            backgroundColor: i < 10 ? Colors.green.shade800 : Colors.red.shade900,
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(tempOrden[i].nombre,
                              style: TextStyle(color: i < 10 ? Colors.greenAccent : Colors.redAccent)),
                          trailing: const Icon(Icons.drag_handle, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance.collection('config').doc('plantel').set({
                      'titulares': tempOrden.map((j) => j.toMap()).toList(),
                    }, SetOptions(merge: true));
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Guardar Nuevo Orden'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docRefConfig = FirebaseFirestore.instance.collection('config').doc('camisetas');

    return StreamBuilder<DocumentSnapshot>(
      stream: docRefConfig.snapshots(),
      builder: (context, snapshotConfig) {
        Map<String, dynamic> dataConfig = {};
        if (snapshotConfig.hasData && snapshotConfig.data!.exists) {
          dataConfig = snapshotConfig.data!.data() as Map<String, dynamic>;
        }

        final nombresTitulares = titulares.map((t) => t.nombre).toList();

        List<String> listaCamisetasAlfabeticas = List.from(nombresTitulares)
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        String lasTieneGuardado = dataConfig['lasTiene'] ??
            (listaCamisetasAlfabeticas.isNotEmpty ? listaCamisetasAlfabeticas.first : 'Sin asignar');
        int indexActual =
            listaCamisetasAlfabeticas.indexWhere((j) => sonElMismoJugador(j, lasTieneGuardado));
        String nombreVisibleLasTiene = lasTieneGuardado;
        String leTocaLlevarlas = 'Sin asignar';

        if (listaCamisetasAlfabeticas.isNotEmpty) {
          if (indexActual != -1) {
            nombreVisibleLasTiene = listaCamisetasAlfabeticas[indexActual];
            leTocaLlevarlas = listaCamisetasAlfabeticas[
                (indexActual + 1) % listaCamisetasAlfabeticas.length];
          } else {
            leTocaLlevarlas = listaCamisetasAlfabeticas.first;
          }
        }

        final verdes = nombresTitulares.take(10).toList();
        final rojos = nombresTitulares.skip(10).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: const Color(0xFF16253B),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.dry_cleaning, color: Colors.lightBlueAccent, size: 22),
                              SizedBox(width: 8),
                              Text('Rotación de Camisetas',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          if (esAdmin)
                            IconButton(
                              tooltip: 'Seleccionar quién las tiene',
                              icon: const Icon(Icons.edit, size: 18, color: Colors.lightBlueAccent),
                              onPressed: () => _abrirSelectorCamisetas(
                                  context, listaCamisetasAlfabeticas, nombreVisibleLasTiene),
                            ),
                        ],
                      ),
                      const Divider(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            const CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.white12,
                                child: Icon(Icons.checkroom, color: Colors.white70, size: 18)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Las tiene:',
                                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  Text(nombreVisibleLasTiene,
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.lightBlueAccent.withValues(alpha: 0.12),
                          border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.lightBlueAccent,
                                child: Icon(Icons.arrow_forward, color: Colors.black, size: 18)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Le toca llevarlas:',
                                      style: TextStyle(fontSize: 11, color: Colors.lightBlueAccent)),
                                  Text(leTocaLlevarlas,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.lightBlueAccent)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (esAdmin) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.lightBlueAccent,
                                side: const BorderSide(color: Colors.lightBlueAccent)),
                            icon: const Icon(Icons.done_all, size: 16),
                            label: Text('Confirmar entrega a $leTocaLlevarlas'),
                            onPressed: () async => await docRefConfig
                                .set({'lasTiene': leTocaLlevarlas}, SetOptions(merge: true)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Lista de Rotación',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  if (esAdmin)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orangeAccent.withValues(alpha: 0.2),
                            foregroundColor: Colors.orangeAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          icon: const Icon(Icons.people_alt, size: 16),
                          label: const Text('Plantel',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: onAbrirGestionPlantel,
                        ),
                        const SizedBox(width: 6),
                        TextButton.icon(
                          style:
                              TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                          icon: const Icon(Icons.swap_vert, size: 15, color: Colors.lightBlueAccent),
                          label: const Text('Reordenar',
                              style: TextStyle(
                                  color: Colors.lightBlueAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                          onPressed: () => _abrirEditorCola(context),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Icon(Icons.shield, color: Colors.greenAccent, size: 16),
                    SizedBox(width: 6),
                    Text('LUGAR ASEGURADO / PRIORIDAD (1 - 10)',
                        style: TextStyle(
                            color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (verdes.isEmpty)
                Card(
                  color: Colors.white.withValues(alpha: 0.02),
                  child: const Padding(
                    padding: EdgeInsets.all(14.0),
                    child: Center(
                        child: Text('No hay titulares en rotación. Andá a "Plantel" para cargarlos.',
                            style: TextStyle(color: Colors.grey))),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: verdes.length,
                  itemBuilder: (context, index) {
                    final jugador = verdes[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: const Color(0xFF14291E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.3)),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 13,
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          child: Text('${index + 1}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(jugador,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        trailing: const Text('Titular asegurado',
                            style: TextStyle(
                                fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.w600)),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                    SizedBox(width: 6),
                    Text('EN RIESGO / COLA DE ESPERA (11 - 15)',
                        style: TextStyle(
                            color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (rojos.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('No hay jugadores en riesgo de rotación.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rojos.length,
                  itemBuilder: (context, index) {
                    final jugador = rojos[index];
                    final pos = index + 11;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: const Color(0xFF2D1515),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 13,
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          child: Text('$pos',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(jugador,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                        trailing: Text(
                          '${index + 1}° en entrar si hay baja',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                ),
              if (suplentes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.swap_vert, color: Colors.orangeAccent, size: 16),
                          SizedBox(width: 6),
                          Text('SUPLENTES / RESERVAS',
                              style: TextStyle(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ],
                      ),
                      Text('${suplentes.length}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: suplentes.length,
                  itemBuilder: (context, index) {
                    final j = suplentes[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: Colors.white.withValues(alpha: 0.02),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline, size: 18, color: Colors.grey),
                        title: Text(j.nombre,
                            style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        trailing: const Text('Reserva',
                            style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}