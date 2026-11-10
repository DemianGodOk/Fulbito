import 'package:flutter/material.dart';

class Jugador {
  String nombre;
  String email;
  String uid;
  bool esModerador;
  bool baneado;
  String telefono;

  Jugador({
    required this.nombre,
    this.email = '',
    this.uid = '',
    this.esModerador = false,
    this.baneado = false,
    this.telefono = '',
  });

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'email': email,
        'uid': uid,
        'esModerador': esModerador,
        'baneado': baneado,
        'telefono': telefono,
      };

  factory Jugador.fromMap(Map<String, dynamic> map) => Jugador(
        nombre: (map['nombre'] ?? '').toString(),
        email: (map['email'] ?? '').toString(),
        uid: (map['uid'] ?? '').toString(),
        esModerador: (map['esModerador'] ?? false) as bool,
        baneado: (map['baneado'] ?? false) as bool,
        telefono: (map['telefono'] ?? '').toString(),
      );
}

String limpiarNombre(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final limpio = raw.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  final lower = limpio.toLowerCase();
  if (lower == 'jugador s.v.f.c.' ||
      lower == 'jugador svfc' ||
      lower == 'jugador') {
    return '';
  }
  return limpio;
}

String sanitizarNombreUsuario({
  String? nombre,
  String? email,
}) {
  final nombreLimpio = limpiarNombre(nombre);
  if (nombreLimpio.isNotEmpty) {
    return nombreLimpio;
  }

  final emailLimpio = (email ?? '').trim();
  if (emailLimpio.contains('@')) {
    final localPart = emailLimpio.split('@').first.trim();
    if (localPart.isNotEmpty) {
      return localPart[0].toUpperCase() +
          (localPart.length > 1 ? localPart.substring(1).toLowerCase() : '');
    }
  }

  return 'Jugador';
}

String nombreLegibleUsuario(Map<String, dynamic> u) {
  final raw = (u['nombre'] ?? '').toString();
  final limpio = limpiarNombre(raw);
  if (limpio.isNotEmpty) return limpio;

  final email = (u['email'] ?? '').toString().trim();
  if (email.contains('@')) {
    final pre = email.split('@').first.trim();
    if (pre.isNotEmpty) {
      return pre[0].toUpperCase() +
          (pre.length > 1 ? pre.substring(1).toLowerCase() : '');
    }
  }

  return 'Jugador';
}

String normalizar(String s) {
  var res = limpiarNombre(s).trim().toLowerCase();
  res = res.replaceAll(RegExp(r'[0-9]+$'), '');
  res = res
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');
  return res;
}

bool sonElMismoJugador(String nombreA, String nombreB) {
  final a = normalizar(nombreA);
  final b = normalizar(nombreB);
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
  const dias = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo'
  ];
  const meses = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre'
  ];
  return '${dias[date.weekday - 1]} ${date.day} de ${meses[date.month - 1]}';
}

DateTime? parsearFechaEspanol(String texto) {
  try {
    final match =
        RegExp(r'(\d+)\s+de\s+(\w+)', caseSensitive: false).firstMatch(texto);
    if (match != null) {
      final dia = int.tryParse(match.group(1)!) ?? 1;
      final mesNombre = match.group(2)!.toLowerCase();
      const meses = [
        'enero',
        'febrero',
        'marzo',
        'abril',
        'mayo',
        'junio',
        'julio',
        'agosto',
        'septiembre',
        'octubre',
        'noviembre',
        'diciembre'
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

  for (final j in plantel) {
    final jEmail = j.email.toLowerCase().trim();
    final jUid = j.uid.trim();
    final matchEmail = jEmail.isNotEmpty && jEmail == emailLimpio;
    final matchUid =
        jUid.isNotEmpty && uidLimpio.isNotEmpty && jUid == uidLimpio;
    if (matchEmail || matchUid) {
      if (j.nombre.trim().isNotEmpty) return j.nombre.trim();
    }
  }

  for (final j in plantel) {
    if (j.nombre.trim().isNotEmpty && sonElMismoJugador(j.nombre, nombreGoogle)) {
      return j.nombre.trim();
    }
  }

  final limpio = limpiarNombre(nombreGoogle);
  if (limpio.isNotEmpty) {
    final primer = limpio.split(RegExp(r'\s+')).first.trim();
    if (primer.isNotEmpty) return primer;
  }

  if (emailLimpio.isNotEmpty && emailLimpio.contains('@')) {
    final pre = emailLimpio.split('@').first.trim();
    if (pre.isNotEmpty) {
      return pre[0].toUpperCase() +
          (pre.length > 1 ? pre.substring(1).toLowerCase() : '');
    }
  }

  return 'Jugador';
}

bool esVersionMayor(String nueva, String actual) {
  final List<int> vNueva =
      nueva.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final List<int> vActual =
      actual.split('.').map((e) => int.tryParse(e) ?? 0).toList();

  for (int i = 0; i < 3; i++) {
    final int n = i < vNueva.length ? vNueva[i] : 0;
    final int a = i < vActual.length ? vActual[i] : 0;
    if (n > a) return true;
    if (n < a) return false;
  }

  return false;
}
