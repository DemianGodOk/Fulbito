import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../constants.dart';
import '../../models/jugador.dart';
import '../principal/pantalla_principal.dart';

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
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');

      final UserCredential cred = kIsWeb
          ? await FirebaseAuth.instance.signInWithPopup(googleProvider)
          : await FirebaseAuth.instance.signInWithProvider(googleProvider);

      final user = cred.user;
      if (user != null) {
        final String nombreGuardar = sanitizarNombreUsuario(
          nombre: user.displayName,
          email: user.email,
        );

        final docRef =
            FirebaseFirestore.instance.collection('usuarios').doc(user.uid);
        final docSnap = await docRef.get();
        final bool esNuevo = !docSnap.exists;

        await docRef.set({
          'uid': user.uid,
          'nombre': nombreGuardar,
          'email': user.email ?? '',
          'fotoUrl': user.photoURL,
          'ultimoAcceso': FieldValue.serverTimestamp(),
          if (esNuevo) 'creadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (esNuevo) {
          await FirebaseFirestore.instance.collection('partidos').doc('actual').set({
            'alertaNuevoUsuario': {
              'nombre': nombreGuardar,
              'email': user.email ?? '',
              'timestamp': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar sesión: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
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
          nombreJugador: sanitizarNombreUsuario(
            nombre: user.displayName,
            email: user.email,
          ),
          emailJugador: user.email ?? '',
          fotoUrl: user.photoURL,
          onCerrarSesion: _cerrarSesion,
        );
      },
    );
  }
}

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
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset('assets/logo.jpg', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Fulbito',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Fulbito - Gestión de partidos.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey[400], height: 1.4),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: onLogin,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey.shade700),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Colors.white10,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.g_mobiledata, size: 30, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Continuar con Google',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
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
