import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants.dart';
import '../../models/jugador.dart';
import '../../utils/notificaciones.dart';
import '../../utils/ota_update.dart';
import '../tabs/convocatoria_screen.dart';
import '../tabs/tabla_screen.dart';
import '../tabs/rotacion_screen.dart';
import '../tabs/vestuario_screen.dart';
import '../admin/gestion_plantel_screen.dart';

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
  DateTime _ultimoRegistroNotificado = DateTime.now();
  int _ultimoHistorialAlertaProcesadoTs = DateTime.now().millisecondsSinceEpoch;
  String _ultimaSemanaVerificadaClave = '';
  bool _notifChatHabilitada = true;
  String _ultimaConfigNotifKey = '';

  // AGREGADO: Guardamos los streams en memoria para que no se destruyan con cada setState
  late final Stream<DocumentSnapshot> _streamPartido;
  late final Stream<DocumentSnapshot> _streamPlantel;

  @override
  void initState() {
    super.initState();
    _ultimoRegistroNotificado = DateTime.now();
    gEnPantallaVestuario = false;
    
    // Inicializamos los streams una sola vez al abrir la pantalla
    _streamPartido = FirebaseFirestore.instance.collection('partidos').doc('actual').snapshots();
    _streamPlantel = FirebaseFirestore.instance.collection('config').doc('plantel').snapshots();

    _cargarPreferenciasNotificaciones();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        verificarActualizacionGitHub(context);
      }
    });
  }

  @override
  void dispose() {
    gEnPantallaVestuario = false;
    super.dispose();
  }

  Future<void> _cargarPreferenciasNotificaciones() async {
    final prefs = await SharedPreferences.getInstance();
    bool habilitada = prefs.getBool('notif_chat_habilitada') ?? true;
    final int? ultimoTsGuardado = prefs.getInt('ultimo_alerta_asistencia_id');
    if (ultimoTsGuardado != null) {
      _ultimoHistorialAlertaProcesadoTs = ultimoTsGuardado;
    } else {
      await prefs.setInt(
        'ultimo_alerta_asistencia_id',
        _ultimoHistorialAlertaProcesadoTs,
      );
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .get();
        if (userDoc.exists && userDoc.data()?['notifChat'] != null) {
          habilitada = userDoc.data()!['notifChat'] as bool;
          await prefs.setBool('notif_chat_habilitada', habilitada);
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _notifChatHabilitada = habilitada;
        _ultimaConfigNotifKey = '';
      });
    }
  }

  Future<void> _toggleNotifChat(String aliasUsuario) async {
    final nuevoValor = !_notifChatHabilitada;
    setState(() {
      _notifChatHabilitada = nuevoValor;
      _ultimaConfigNotifKey = '$aliasUsuario-$_esAdmin-$nuevoValor';
    });

    await configurarSuscripcionesNotificaciones(
      alias: aliasUsuario,
      esAdmin: _esAdmin,
      chatHabilitado: nuevoValor,
    );

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .set({'notifChat': nuevoValor}, SetOptions(merge: true));
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nuevoValor
                ? '🔔 Notificaciones del chat activadas'
                : '🔕 Notificaciones del chat desactivadas',
          ),
          backgroundColor: nuevoValor ? Colors.teal : Colors.blueGrey,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _procesarColaAlertasAsistencia(
    List<dynamic> historialAlertas,
    String aliasUsuario,
  ) async {
    if (kIsWeb || !_esAdmin || historialAlertas.isEmpty) return;

    final List<Map<String, dynamic>> pendientes = [];
    for (final item in historialAlertas) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final int ts = (map['ts'] as num?)?.toInt() ?? 0;
        if (ts > _ultimoHistorialAlertaProcesadoTs) {
          pendientes.add(map);
        }
      }
    }

    if (pendientes.isEmpty) return;

    pendientes.sort(
      (a, b) => ((a['ts'] as num?)?.toInt() ?? 0)
          .compareTo((b['ts'] as num?)?.toInt() ?? 0),
    );

    final int maxTs = (pendientes.last['ts'] as num?)?.toInt() ??
        _ultimoHistorialAlertaProcesadoTs;
    _ultimoHistorialAlertaProcesadoTs = maxTs;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ultimo_alerta_asistencia_id', maxTs);

    for (final alerta in pendientes) {
      final String nombre = (alerta['nombre'] ?? '').toString();
      final String tipo = (alerta['tipo'] ?? '').toString();
      final int notifId = (alerta['id'] as num?)?.toInt() ??
          (((alerta['ts'] as num?)?.toInt() ?? 0) % 100000000);

      if (nombre.isEmpty || sonElMismoJugador(nombre, aliasUsuario)) continue;

      final esNueva = await marcarNotificacionComoMostrada(notifId);
      if (!esNueva) continue;

      if (tipo == 'confirmado') {
        await mostrarNotificacion(
          id: notifId,
          titulo: '✅ Confirmación de asistencia',
          cuerpo: '$nombre confirmó que va a jugar este partido.',
        );
      } else if (tipo == 'baja') {
        await mostrarNotificacion(
          id: notifId,
          titulo: '⚠️ Baja registrada',
          cuerpo: '$nombre avisó que no juega este partido.',
        );
      }
    }
  }

  bool get _esAdmin =>
      kBypassLogin ||
      widget.emailJugador.toLowerCase().trim() == kSuperAdminEmail.toLowerCase().trim();

  String? get _fotoUrlConProxy {
    if (widget.fotoUrl == null || widget.fotoUrl!.isEmpty) return null;
    return 'https://images.weserv.nl/?url=${Uri.encodeComponent(widget.fotoUrl!)}';
  }

  void _revisarProgramacionRecordatorio(Map<String, dynamic> datosPartido) {
    if (kIsWeb) return;

    final int? millis = datosPartido['recordatorioMillis'] as int?;
    final String partidoTexto =
        '${datosPartido['dia'] ?? ''} a las ${datosPartido['hora'] ?? ''}'.trim();

    if (millis != null) {
      final key = '$millis-$partidoTexto';
      if (_ultimoRecordatorioProgramado != key) {
        _ultimoRecordatorioProgramado = key;
        final dt = DateTime.fromMillisecondsSinceEpoch(millis);
        programarRecordatorioAsistencia(
          fechaHora: dt,
          partidoTexto: partidoTexto,
        );
      }
    }
  }

  void _verificarYActualizarSemanaPartido(
    Map<String, dynamic> datosPartido, {
    required List<Jugador> titulares,
  }) async {
    if (!_esAdmin) return;

    if (_verificandoSemana) return;

    DateTime? fechaPartido;
    if (datosPartido['fechaMillis'] != null) {
      fechaPartido = DateTime.fromMillisecondsSinceEpoch(
        datosPartido['fechaMillis'] as int,
      );
    } else if (datosPartido['dia'] != null) {
      fechaPartido = parsearFechaEspanol(datosPartido['dia'].toString());
    }

    if (fechaPartido == null) return;

    final hoy = DateTime.now();
    // Reset automático exactamente a las 0hs del día siguiente del partido
    final fechaLimiteActual =
        DateTime(fechaPartido.year, fechaPartido.month, fechaPartido.day + 1, 0, 0, 0);

    final claveActual = '${fechaPartido.millisecondsSinceEpoch}';
    if (_ultimaSemanaVerificadaClave == claveActual &&
        !hoy.isAfter(fechaLimiteActual)) {
      return;
    }

    if (!hoy.isAfter(fechaLimiteActual)) {
      _ultimaSemanaVerificadaClave = claveActual;
      return;
    }

    _verificandoSemana = true;
    try {
      DateTime nuevaFecha = fechaPartido.add(const Duration(days: 7));
      while (DateTime(
        nuevaFecha.year,
        nuevaFecha.month,
        nuevaFecha.day + 1,
        0, 0, 0,
      ).isBefore(hoy)) {
        nuevaFecha = nuevaFecha.add(const Duration(days: 7));
      }

      final nuevoDiaTexto = formatearFechaEspanol(nuevaFecha);

      int? nuevoRecordatorioMillis;
      if (datosPartido['recordatorioMillis'] != null) {
        DateTime recDt = DateTime.fromMillisecondsSinceEpoch(
          datosPartido['recordatorioMillis'] as int,
        ).add(const Duration(days: 7));
        while (recDt.isBefore(hoy)) {
          recDt = recDt.add(const Duration(days: 7));
        }
        nuevoRecordatorioMillis = recDt.millisecondsSinceEpoch;
      }

      // 1. Obtener datos actuales de camisetas y asistencia para la transición automática
      final Map<String, dynamic> asistenciaPrevia =
          (datosPartido['asistencia'] as Map<String, dynamic>?) ?? {};

      final docCamisetasRef = FirebaseFirestore.instance.collection('config').doc('camisetas');
      final snapCamisetas = await docCamisetasRef.get();
      if (snapCamisetas.exists && snapCamisetas.data() != null) {
        final dataCamisetas = snapCamisetas.data()!;
        final Map<String, dynamic> conteo = Map<String, dynamic>.from(dataCamisetas['conteo'] ?? {});
        final String deudor = (dataCamisetas['deudorCamisetas'] ?? '').toString().trim();
        final String manual = (dataCamisetas['leTocaManual'] ?? '').toString().trim();
        final String actualTiene = (dataCamisetas['lasTiene'] ?? '').toString().trim();

        final nombresTitulares = titulares.map((t) => t.nombre).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        if (nombresTitulares.isNotEmpty) {
          String estadoDe(String nombre) {
            for (final k in asistenciaPrevia.keys) {
              if (sonElMismoJugador(k, nombre)) {
                return (asistenciaPrevia[k] ?? '').toString();
              }
            }
            return '';
          }

          int idxActual = nombresTitulares.indexWhere((j) => sonElMismoJugador(j, actualTiene));
          if (idxActual == -1) idxActual = 0;

          String destinatario = '';
          String salteado = '';

          if (manual.isNotEmpty && estadoDe(manual) != 'baja') {
            destinatario = manual;
          } else {
            if (manual.isNotEmpty && estadoDe(manual) == 'baja') {
              salteado = manual;
            }

            if (deudor.isNotEmpty && estadoDe(deudor) == 'confirmado') {
              destinatario = deudor;
            } else {
              final sig = nombresTitulares[(idxActual + 1) % nombresTitulares.length];
              if (estadoDe(sig) == 'baja') {
                if (salteado.isEmpty) salteado = sig;
                for (int step = 2; step <= nombresTitulares.length; step++) {
                  final cand = nombresTitulares[(idxActual + step) % nombresTitulares.length];
                  if (estadoDe(cand) != 'baja') {
                    destinatario = cand;
                    break;
                  }
                }
                if (destinatario.isEmpty) destinatario = sig;
              } else {
                destinatario = sig;
              }
            }
          }

          if (destinatario.isNotEmpty) {
            final int prevCount = (conteo[destinatario] ?? 0) as int;
            conteo[destinatario] = prevCount + 1;

            String nuevoDeudor = deudor;
            if (destinatario == deudor) {
              nuevoDeudor = '';
            } else if (salteado.isNotEmpty) {
              nuevoDeudor = salteado;
            }

            await docCamisetasRef.set({
              'lasTiene': destinatario,
              'conteo': conteo,
              'deudorCamisetas': nuevoDeudor,
              'leTocaManual': FieldValue.delete(),
            }, SetOptions(merge: true));
          }
        }
      }

      // 2. Actualizar partido con nueva fecha, recordatorio actualizado y limpiar convocatoria
      await FirebaseFirestore.instance.collection('partidos').doc('actual').set({
        'dia': nuevoDiaTexto,
        'fechaMillis': nuevaFecha.millisecondsSinceEpoch,
        if (nuevoRecordatorioMillis != null) 'recordatorioMillis': nuevoRecordatorioMillis,
        'asistencia': FieldValue.delete(),
        'ultimaAlerta': FieldValue.delete(),
      }, SetOptions(merge: true));

      _ultimaSemanaVerificadaClave = '${nuevaFecha.millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('Error al actualizar fecha semanal del partido: $e');
    } finally {
      _verificandoSemana = false;
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
              await FirebaseFirestore.instance
                  .collection('partidos')
                  .doc('actual')
                  .update({
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

  void _mostrarDialogoConfiguracion(
    BuildContext context,
    Map<String, dynamic> datosActuales,
  ) {
    final diaCtrl = TextEditingController(
      text: datosActuales['dia'] ?? 'Viernes 30 de Octubre',
    );
    final horaCtrl =
        TextEditingController(text: datosActuales['hora'] ?? '20:00 hs');
    final lugarCtrl = TextEditingController(
      text: datosActuales['lugar'] ?? 'Estación 98 - Cancha 2',
    );
    final mapsUrlCtrl =
        TextEditingController(text: (datosActuales['mapsUrl'] ?? '').toString());
    final cupoCtrl =
        TextEditingController(text: '${datosActuales['cupoMaximo'] ?? 10}');
    final nombreTorneoCtrl = TextEditingController(
      text: (datosActuales['nombreTorneo'] ?? kNombreTorneo).toString(),
    );

    final recDiaCtrl = TextEditingController(
      text: datosActuales['recordatorioDia'] ?? 'Jueves anterior',
    );
    final recHoraCtrl = TextEditingController(
      text: datosActuales['recordatorioHora'] ?? '10:00 hs',
    );

    final fechaInicioTorneoCtrl = TextEditingController(
      text: (datosActuales['fechaInicioTorneo'] ?? '').toString(),
    );
    final fechaFinTorneoCtrl = TextEditingController(
      text: (datosActuales['fechaFinTorneo'] ?? '').toString(),
    );

    DateTime? fechaInicioTorneoSeleccionada = datosActuales['fechaInicioTorneoMillis'] != null
        ? DateTime.fromMillisecondsSinceEpoch(datosActuales['fechaInicioTorneoMillis'] as int)
        : null;

    DateTime? fechaFinTorneoSeleccionada = datosActuales['fechaFinTorneoMillis'] != null
        ? DateTime.fromMillisecondsSinceEpoch(datosActuales['fechaFinTorneoMillis'] as int)
        : null;

    DateTime fechaPartidoSeleccionada = datosActuales['fechaMillis'] != null
        ? DateTime.fromMillisecondsSinceEpoch(datosActuales['fechaMillis'] as int)
        : (parsearFechaEspanol(datosActuales['dia'] ?? '') ?? DateTime.now());

    DateTime fechaRecordatorioSeleccionada = datosActuales['recordatorioMillis'] != null
        ? DateTime.fromMillisecondsSinceEpoch(
            datosActuales['recordatorioMillis'] as int)
        : DateTime.now().add(const Duration(days: 1));

    TimeOfDay horaRecordatorioSeleccionada = datosActuales['recordatorioMillis'] != null
        ? TimeOfDay.fromDateTime(fechaRecordatorioSeleccionada)
        : const TimeOfDay(hour: 10, minute: 0);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.lightBlueAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Configurar Torneo',
                  style: TextStyle(fontSize: 17),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nombreTorneoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Torneo',
                    prefixIcon: Icon(
                      Icons.emoji_events_outlined,
                      color: Colors.lightBlueAccent,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fechaInicioTorneoCtrl,
                        readOnly: true,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: fechaInicioTorneoSeleccionada ?? DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setDlgState(() {
                              fechaInicioTorneoSeleccionada = picked;
                              fechaInicioTorneoCtrl.text = formatearFechaEspanol(picked);
                            });
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Inicio Torneo',
                          prefixIcon: Icon(Icons.date_range, color: Colors.tealAccent, size: 18),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: fechaFinTorneoCtrl,
                        readOnly: true,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: fechaFinTorneoSeleccionada ?? DateTime.now().add(const Duration(days: 60)),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setDlgState(() {
                              fechaFinTorneoSeleccionada = picked;
                              fechaFinTorneoCtrl.text = formatearFechaEspanol(picked);
                            });
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Fin Torneo',
                          prefixIcon: Icon(Icons.flag_outlined, color: Colors.amberAccent, size: 18),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                    labelText: 'Fecha del Partido Actual',
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
                    labelText: 'Cancha / Dirección',
                    prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mapsUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Link de Google Maps',
                    prefixIcon: Icon(Icons.map_outlined, size: 20),
                    hintText: 'https://maps.google.com/...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cupoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cupo Total de Jugadores',
                    prefixIcon: Icon(Icons.people_alt_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const Row(
                  children: [
                    Icon(Icons.alarm, color: Colors.tealAccent, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Recordatorio de Confirmación',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.tealAccent,
                      ),
                    ),
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
                      firstDate: DateTime(2024),
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
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
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
                  'nombreTorneo': nombreTorneoCtrl.text.trim().isNotEmpty
                      ? nombreTorneoCtrl.text.trim()
                      : kNombreTorneo,
                  'fechaInicioTorneo': fechaInicioTorneoCtrl.text.trim(),
                  'fechaInicioTorneoMillis': fechaInicioTorneoSeleccionada?.millisecondsSinceEpoch,
                  'fechaFinTorneo': fechaFinTorneoCtrl.text.trim(),
                  'fechaFinTorneoMillis': fechaFinTorneoSeleccionada?.millisecondsSinceEpoch,
                  'dia': diaCtrl.text.trim(),
                  'fechaMillis': fechaPartidoSeleccionada.millisecondsSinceEpoch,
                  'hora': horaCtrl.text.trim(),
                  'lugar': lugarCtrl.text.trim(),
                  'mapsUrl': mapsUrlCtrl.text.trim(),
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
      // USAMOS LA VARIABLE CACHEADA
      stream: _streamPartido,
      builder: (context, snapshotPartido) {
        if (snapshotPartido.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshotPartido.hasData ||
            snapshotPartido.data == null ||
            !snapshotPartido.data!.exists) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final infoPartido = (snapshotPartido.data!.data() as Map<String, dynamic>?) ?? {};

        return StreamBuilder<DocumentSnapshot>(
          // USAMOS LA VARIABLE CACHEADA
          stream: _streamPlantel,
          builder: (context, snapshotPlantel) {
            
            if (snapshotPlantel.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (!snapshotPlantel.hasData || !snapshotPlantel.data!.exists) {
               return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            List<Jugador> titularesActuales = [];
            List<Jugador> suplentesActuales = [];
            List<String> baneadosGlobal = [];

            final data = snapshotPlantel.data!.data() as Map<String, dynamic>?;

            if (data != null) {
              if (data['titulares'] != null) {
                titularesActuales = (data['titulares'] as List)
                    .map((e) => Jugador.fromMap(Map<String, dynamic>.from(e)))
                    .toList();
              }
              if (data['suplentes'] != null) {
                suplentesActuales = (data['suplentes'] as List)
                    .map((e) => Jugador.fromMap(Map<String, dynamic>.from(e)))
                    .toList();
              }
              if (data['baneados'] != null) {
                baneadosGlobal = (data['baneados'] as List)
                    .map((e) => e.toString().toLowerCase().trim())
                    .toList();
              }
            }
            

            final todos = [...titularesActuales, ...suplentesActuales];
            final aliasUsuario = resolverAliasOPrimerNombre(
              nombreGoogle: widget.nombreJugador,
              emailGoogle: widget.emailJugador,
              uidGoogle: FirebaseAuth.instance.currentUser?.uid,
              plantel: todos,
            );

            final configNotifKey = '$aliasUsuario-$_esAdmin-$_notifChatHabilitada';
            if (_ultimaConfigNotifKey != configNotifKey) {
              _ultimaConfigNotifKey = configNotifKey;
              configurarSuscripcionesNotificaciones(
                alias: aliasUsuario,
                esAdmin: _esAdmin,
                chatHabilitado: _notifChatHabilitada,
              );
            }

            final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
            final currentEmail = widget.emailJugador.toLowerCase().trim();
            final bool esBaneado = baneadosGlobal.contains(currentEmail) ||
                (currentUid.isNotEmpty && baneadosGlobal.contains(currentUid.toLowerCase())) ||
                todos.any((j) => j.baneado && (sonElMismoJugador(j.nombre, aliasUsuario) || j.email.toLowerCase().trim() == currentEmail));

            if (_esAdmin) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _verificarYActualizarSemanaPartido(
                  infoPartido,
                  titulares: titularesActuales,
                );
              });
            }

            if (!kIsWeb && _esAdmin && infoPartido['historialAlertas'] is List) {
              _procesarColaAlertasAsistencia(
                infoPartido['historialAlertas'] as List,
                aliasUsuario,
              );
            }

            if (!kIsWeb && _esAdmin && infoPartido['alertaNuevoUsuario'] != null) {
              final alertaReg = infoPartido['alertaNuevoUsuario'];
              if (alertaReg is Map<String, dynamic>) {
                final ts = (alertaReg['timestamp'] as Timestamp?)?.toDate();
                if (ts != null && ts.isAfter(_ultimoRegistroNotificado)) {
                  _ultimoRegistroNotificado = ts;
                  final regEmail =
                      (alertaReg['email'] ?? '').toString().toLowerCase().trim();
                  if (regEmail != widget.emailJugador.toLowerCase().trim()) {
                    mostrarNotificacion(
                      id: 102,
                      titulo: '👤 Nuevo registro en Fulbito',
                      cuerpo:
                          '${alertaReg['nombre']} ($regEmail) se acaba de registrar en la app.',
                    );
                  }
                }
              }
            }

            _revisarProgramacionRecordatorio(infoPartido);

            final bool esModerador = _esAdmin ||
                todos.any(
                  (j) =>
                      j.esModerador &&
                      (j.email.toLowerCase().trim() ==
                              widget.emailJugador.toLowerCase().trim() ||
                          sonElMismoJugador(j.nombre, aliasUsuario)),
                );

            final List<Widget> pantallas = [
              ConvocatoriaScreen(
                nombreJugador: aliasUsuario,
                emailJugador: widget.emailJugador,
                infoPartido: infoPartido,
                esAdmin: _esAdmin,
                esBaneado: esBaneado,
                titulares: titularesActuales,
                suplentes: suplentesActuales,
              ),
              TablaScreen(
                esAdmin: _esAdmin,
                puedeCargarResultado: _esAdmin || esModerador,
                nombreJugador: aliasUsuario,
                titulares: titularesActuales,
                suplentes: suplentesActuales,
              ),
              RotacionScreen(
                esAdmin: _esAdmin,
                titulares: titularesActuales,
                suplentes: suplentesActuales,
                infoPartidoDia: (infoPartido['dia'] ?? '').toString(),
                asistencia: (infoPartido['asistencia'] as Map<String, dynamic>?) ?? {},
                onAbrirGestionPlantel: () => _abrirGestionPlantel(context),
              ),
              VestuarioScreen(aliasUsuario: aliasUsuario),
            ];

            return Scaffold(
              appBar: AppBar(
                leading: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    backgroundImage: AssetImage('assets/logo.jpg'),
                  ),
                ),
                title: const Text(
                  'S.V.F.C. Oficial',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
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
                      } else if (value == 'notif_chat') {
                        _toggleNotifChat(aliasUsuario);
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
                                Text(
                                  aliasUsuario,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (_esAdmin)
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade800,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'ADMIN',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                else if (esModerador)
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade800,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'MODERADOR',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              widget.emailJugador,
                              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                            ),
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
                              Text(
                                'Gestionar plantel',
                                style: TextStyle(color: Colors.orangeAccent),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'settings',
                          child: Row(
                            children: [
                              Icon(Icons.settings, size: 18, color: Colors.lightBlueAccent),
                              SizedBox(width: 8),
                              Text(
                                'Configurar torneo',
                                style: TextStyle(color: Colors.lightBlueAccent),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'reset',
                          child: Row(
                            children: [
                              Icon(Icons.restart_alt, size: 18, color: Colors.amberAccent),
                              SizedBox(width: 8),
                              Text(
                                'Resetear convocatoria',
                                style: TextStyle(color: Colors.amberAccent),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                      ],
                      if (!kIsWeb) ...[
                        PopupMenuItem(
                          value: 'notif_chat',
                          child: Row(
                            children: [
                              Icon(
                                _notifChatHabilitada
                                    ? Icons.notifications_active
                                    : Icons.notifications_off_outlined,
                                size: 18,
                                color: _notifChatHabilitada
                                    ? Colors.tealAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Notificación del chat',
                                  style: TextStyle(
                                    color: _notifChatHabilitada
                                        ? Colors.white
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _notifChatHabilitada
                                      ? Colors.tealAccent.withValues(alpha: 0.2)
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _notifChatHabilitada ? 'ON' : 'OFF',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _notifChatHabilitada
                                        ? Colors.tealAccent
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
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
              body: IndexedStack(
                index: _indiceActual,
                children: pantallas,
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _indiceActual,
                onDestinationSelected: (int index) {
                  setState(() {
                    _indiceActual = index;
                    gEnPantallaVestuario = (index == 3);
                  });
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.sports_soccer_outlined),
                    selectedIcon: Icon(Icons.sports_soccer),
                    label: 'Partido',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.leaderboard_outlined),
                    selectedIcon: Icon(Icons.leaderboard),
                    label: 'Tabla',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.sync_alt_outlined),
                    selectedIcon: Icon(Icons.sync_alt),
                    label: 'Rotación',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.forum_outlined),
                    selectedIcon: Icon(Icons.forum),
                    label: 'Vestuario',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
