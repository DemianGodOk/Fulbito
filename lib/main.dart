import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'constants.dart';
import 'utils/notificaciones.dart';
import 'screens/auth/login_screen.dart';

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
          apiKey: 'AIzaSyBcalfFCa9fKb-VnY0hQFd9ehTr51I2lk8',
          authDomain: 'fulbito-svfc.firebaseapp.com',
          projectId: 'fulbito-svfc',
          storageBucket: 'fulbito-svfc.firebasestorage.app',
          messagingSenderId: '112754897657',
          appId: '1:112754897657:web:a52806ee7db2c045322828',
        ),
      );
    } else {
      await Firebase.initializeApp();
      await inicializarNotificaciones();
    }
  } catch (e) {
    debugPrint('Error al inicializar Firebase: $e');
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
