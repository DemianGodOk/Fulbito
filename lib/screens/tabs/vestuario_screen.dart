import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/jugador.dart';
import '../../utils/notificaciones.dart';

class VestuarioScreen extends StatefulWidget {
  final String aliasUsuario;
  final String emailUsuario;
  final String uidUsuario;
  final List<Jugador> titulares;
  final List<Jugador> suplentes;

  const VestuarioScreen({
    super.key,
    required this.aliasUsuario,
    this.emailUsuario = '',
    this.uidUsuario = '',
    this.titulares = const [],
    this.suplentes = const [],
  });

  @override
  State<VestuarioScreen> createState() => _VestuarioScreenState();
}

class _VestuarioScreenState extends State<VestuarioScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _enviando = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _resolverAutorActual(Map<String, dynamic> data) {
    final String autorGuardado = (data['autor'] ?? 'Anónimo').toString();
    final String autorEmail =
        (data['autorEmail'] ?? '').toString().toLowerCase().trim();

    final todos = [...widget.titulares, ...widget.suplentes];

    if (autorEmail.isNotEmpty) {
      for (final j in todos) {
        if (j.email.toLowerCase().trim() == autorEmail &&
            j.nombre.trim().isNotEmpty) {
          return j.nombre.trim();
        }
      }
    }

    return autorGuardado;
  }

  bool _esMensajeMio(Map<String, dynamic> data, String autorMostrado) {
    final String autorUid = (data['autorUid'] ?? '').toString().trim();
    final String autorEmail =
        (data['autorEmail'] ?? '').toString().toLowerCase().trim();
    final String miEmail = widget.emailUsuario.toLowerCase().trim();

    if (widget.uidUsuario.isNotEmpty &&
        autorUid.isNotEmpty &&
        autorUid == widget.uidUsuario) {
      return true;
    }
    if (miEmail.isNotEmpty &&
        autorEmail.isNotEmpty &&
        autorEmail == miEmail) {
      return true;
    }
    return sonElMismoJugador(autorMostrado, widget.aliasUsuario);
  }

  Future<void> _enviarMensaje() async {
    final texto = _msgCtrl.text.trim();
    if (texto.isEmpty) return;

    setState(() => _enviando = true);

    try {
      final int notifId = DateTime.now().millisecondsSinceEpoch % 100000000;

      await FirebaseFirestore.instance.collection('mensajes').add({
        'texto': texto,
        'autor': widget.aliasUsuario,
        'autorUid': widget.uidUsuario.trim(),
        'autorEmail': widget.emailUsuario.toLowerCase().trim(),
        'ts': FieldValue.serverTimestamp(),
      });

      _msgCtrl.clear();

      enviarPushNotificacion(
        topic: 'chat_fulbito',
        data: {
          'tipo': 'chat',
          'autor': widget.aliasUsuario,
          'autorUid': widget.uidUsuario.trim(),
          'autorEmail': widget.emailUsuario.toLowerCase().trim(),
          'texto': texto,
          'notifId': '$notifId',
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error enviando: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _dialogoVotacionFigura() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF142030),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.star, color: Colors.amberAccent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Figura de la Fecha (MvP)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: VotacionFiguraWidget(
                aliasUsuario: widget.aliasUsuario,
                titulares: widget.titulares,
                suplentes: widget.suplentes,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF142030),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.campaign, color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'El Vestuario',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amberAccent.withValues(alpha: 0.15),
                  foregroundColor: Colors.amberAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.how_to_vote, size: 16),
                label: const Text(
                  'Votar Figura',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                onPressed: _dialogoVotacionFigura,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.black38),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('mensajes')
                .orderBy('ts', descending: true)
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No hay mensajes.\n¡Mandá el primero!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              return ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final texto = data['texto'] ?? '';
                  final autor = _resolverAutorActual(data);
                  final ts = data['ts'] as Timestamp?;
                  String hora = '';
                  if (ts != null) {
                    final dt = ts.toDate();
                    final h = dt.hour.toString().padLeft(2, '0');
                    final m = dt.minute.toString().padLeft(2, '0');
                    hora = '$h:$m';
                  }

                  final esMio = _esMensajeMio(data, autor);

                  return Align(
                    alignment:
                        esMio ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: esMio ? Colors.blue.shade800 : Colors.grey.shade800,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(esMio ? 12 : 0),
                          bottomRight: Radius.circular(esMio ? 0 : 12),
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
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade200,
                                ),
                              ),
                            ),
                          Text(
                            texto,
                            style: const TextStyle(fontSize: 14),
                          ),
                          if (hora.isNotEmpty)
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  hora,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white.withValues(alpha: 0.5),
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
        Container(
          color: const Color(0xFF1E1E1E),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Escribí un mensaje...',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.black26,
                  ),
                  onSubmitted: (_) => _enviarMensaje(),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.blueAccent,
                child: IconButton(
                  icon: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: _enviando ? null : _enviarMensaje,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class VotacionFiguraWidget extends StatefulWidget {
  final String aliasUsuario;
  final List<Jugador> titulares;
  final List<Jugador> suplentes;

  const VotacionFiguraWidget({
    super.key,
    required this.aliasUsuario,
    this.titulares = const [],
    this.suplentes = const [],
  });

  @override
  State<VotacionFiguraWidget> createState() => _VotacionFiguraWidgetState();
}

class _VotacionFiguraWidgetState extends State<VotacionFiguraWidget> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _docIdActual;
  String _fechaPartidoStr = '';
  String _nombreTorneoStr = '';
  String _mensajeEspera = '';
  List<String> _jugadores = [];
  String? _jugadorSeleccionado;
  bool _votacionAbierta = true;
  bool _cargando = true;
  bool _yaVote = false;

  @override
  void initState() {
    super.initState();
    _cargarOcrearVotacion();
  }

  String _canonicalizarJugador(String raw, List<String> plantelNombres) {
    final limpio = limpiarNombre(raw);
    final base = limpio.isNotEmpty ? limpio : raw.trim();
    for (final p in plantelNombres) {
      if (sonElMismoJugador(p, base)) {
        return p;
      }
    }
    return base;
  }

  DateTime? _calcularInicioPartido(Map<String, dynamic> dataPartido) {
    DateTime? baseFecha;
    if (dataPartido['fechaMillis'] != null) {
      final raw = dataPartido['fechaMillis'];
      final ms = raw is int ? raw : int.tryParse('$raw');
      if (ms != null) {
        baseFecha = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    baseFecha ??= parsearFechaEspanol((dataPartido['dia'] ?? '').toString());
    if (baseFecha == null) return null;

    int hour = 20;
    int minute = 0;
    final horaStr = (dataPartido['hora'] ?? '').toString();
    final matchHora = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(horaStr);
    if (matchHora != null) {
      hour = int.tryParse(matchHora.group(1)!) ?? 20;
      minute = int.tryParse(matchHora.group(2)!) ?? 0;
    }

    return DateTime(
      baseFecha.year,
      baseFecha.month,
      baseFecha.day,
      hour,
      minute,
    );
  }

  Future<void> _cargarOcrearVotacion() async {
    try {
      final docPartido = await _db.collection('partidos').doc('actual').get();
      final Map<String, dynamic> dataPartido =
          docPartido.exists && docPartido.data() != null
              ? docPartido.data()!
              : {};

      final String diaPartido = (dataPartido['dia'] ?? '').toString().trim();
      final String torneoPartido =
          (dataPartido['nombreTorneo'] ?? '').toString().trim();
      final Map<String, dynamic> asistenciaPartido =
          (dataPartido['asistencia'] as Map<String, dynamic>?) ?? {};

      // Obtener nombres del plantel completo (por widget o Firestore)
      List<String> plantelNombres = [
        ...widget.titulares.map((t) => t.nombre.trim()),
        ...widget.suplentes.map((s) => s.nombre.trim()),
      ]..removeWhere((e) => e.isEmpty);

      if (plantelNombres.isEmpty) {
        final snapPlantel =
            await _db.collection('config').doc('plantel').get();
        if (snapPlantel.exists && snapPlantel.data() != null) {
          final dataP = snapPlantel.data()!;
          final titulares =
              List<Map<String, dynamic>>.from(dataP['titulares'] ?? []);
          final suplentes =
              List<Map<String, dynamic>>.from(dataP['suplentes'] ?? []);
          plantelNombres = [...titulares, ...suplentes]
              .map((e) => (e['nombre'] ?? '').toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }

      // Buscar el último partido jugado en historial_partidos
      final snapHistorial = await _db
          .collection('historial_partidos')
          .orderBy('creadoEn', descending: true)
          .limit(1)
          .get();

      Map<String, dynamic>? ultimoPartidoHistorial;
      if (snapHistorial.docs.isNotEmpty) {
        ultimoPartidoHistorial = snapHistorial.docs.first.data();
      }

      final DateTime? inicioPartidoActual = _calcularInicioPartido(dataPartido);
      final bool partidoActualYaComenzo = inicioPartidoActual != null &&
          DateTime.now().isAfter(inicioPartidoActual);

      List<String> candidatosVotacion = [];

      if (ultimoPartidoHistorial != null &&
          (ultimoPartidoHistorial['fecha'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase() ==
              diaPartido.toLowerCase()) {
        // Caso 1: Ya se cargó el resultado del partido de esta fecha
        _fechaPartidoStr =
            (ultimoPartidoHistorial['fecha'] ?? diaPartido).toString().trim();
        _nombreTorneoStr =
            (ultimoPartidoHistorial['torneo'] ?? torneoPartido).toString().trim();
        final eqA = (ultimoPartidoHistorial['equipoA_jugadores'] as List?) ?? [];
        final eqB = (ultimoPartidoHistorial['equipoB_jugadores'] as List?) ?? [];
        candidatosVotacion = [...eqA, ...eqB]
            .map((j) => _canonicalizarJugador(j.toString(), plantelNombres))
            .where((j) => j.isNotEmpty)
            .toSet()
            .toList();
      } else if (partidoActualYaComenzo && diaPartido.isNotEmpty) {
        // Caso 2: El partido de hoy ya se jugó, aunque todavía no cargaron el marcador
        _fechaPartidoStr = diaPartido;
        _nombreTorneoStr = torneoPartido;
        final confirmados = asistenciaPartido.entries
            .where((e) => e.value == 'confirmado')
            .map((e) => _canonicalizarJugador(e.key, plantelNombres))
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        candidatosVotacion =
            confirmados.isNotEmpty ? confirmados : List.from(plantelNombres);
      } else if (ultimoPartidoHistorial != null &&
          (ultimoPartidoHistorial['fecha'] ?? '').toString().trim().isNotEmpty) {
        // Caso 3: El próximo partido (diaPartido) todavía no se jugó; sigue abierta
        // la votación semanal del último partido jugado
        _fechaPartidoStr =
            (ultimoPartidoHistorial['fecha'] ?? '').toString().trim();
        _nombreTorneoStr =
            (ultimoPartidoHistorial['torneo'] ?? torneoPartido).toString().trim();
        final eqA = (ultimoPartidoHistorial['equipoA_jugadores'] as List?) ?? [];
        final eqB = (ultimoPartidoHistorial['equipoB_jugadores'] as List?) ?? [];
        candidatosVotacion = [...eqA, ...eqB]
            .map((j) => _canonicalizarJugador(j.toString(), plantelNombres))
            .where((j) => j.isNotEmpty)
            .toSet()
            .toList();
      } else {
        // Caso 4: Sin partidos jugados todavía
        _mensajeEspera = diaPartido.isNotEmpty
            ? 'La votación de la figura se habilita después de jugar el partido ($diaPartido).'
            : 'La votación se habilita después de jugar el primer partido.';
        if (mounted) setState(() => _cargando = false);
        return;
      }

      if (candidatosVotacion.isEmpty) {
        candidatosVotacion = List.from(plantelNombres);
      }
      candidatosVotacion.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _jugadores = candidatosVotacion;

      final refVotos = _db.collection('votos_figura');
      final snapVotos = await refVotos
          .where('fechaPartido', isEqualTo: _fechaPartidoStr)
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? docCoincidente;
      for (final d in snapVotos.docs) {
        final tDoc = (d.data()['torneo'] ?? '').toString().trim();
        if (_nombreTorneoStr.isEmpty ||
            tDoc.isEmpty ||
            tDoc == _nombreTorneoStr) {
          docCoincidente = d;
          break;
        }
      }

      if (docCoincidente != null) {
        _docIdActual = docCoincidente.id;
        final dataV = docCoincidente.data();
        _votacionAbierta = dataV['abierta'] ?? true;

        final votosGral = (dataV['votos'] as Map<String, dynamic>?) ?? {};
        final aliasLimpio = _aliasLimpiada(widget.aliasUsuario);
        final claveVoto = votosGral.containsKey(aliasLimpio)
            ? aliasLimpio
            : (votosGral.containsKey(widget.aliasUsuario)
                ? widget.aliasUsuario
                : null);
        if (claveVoto != null && votosGral[claveVoto] is Map) {
          final misAntiguos =
              Map<String, dynamic>.from(votosGral[claveVoto] as Map);
          String? elegidoPrevio;
          int maxPtsPrevio = 0;
          misAntiguos.forEach((k, v) {
            final canon = _canonicalizarJugador(k, plantelNombres);
            final pts = (v is int) ? v : int.tryParse('$v') ?? 0;
            if (canon.isNotEmpty && pts > maxPtsPrevio) {
              maxPtsPrevio = pts;
              elegidoPrevio = canon;
            }
          });
          if (elegidoPrevio != null) {
            _yaVote = true;
            _jugadorSeleccionado = elegidoPrevio;
          }
        }
      } else {
        final nuevoDoc = await refVotos.add({
          'fechaPartido': _fechaPartidoStr,
          'torneo': _nombreTorneoStr,
          'creadoEn': FieldValue.serverTimestamp(),
          'abierta': true,
          'votos': <String, dynamic>{},
        });
        _docIdActual = nuevoDoc.id;
      }
    } catch (e) {
      debugPrint('Error en MvP: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _seleccionarJugador(String jugador) {
    if (_yaVote || !_votacionAbierta) return;
    setState(() {
      _jugadorSeleccionado =
          (_jugadorSeleccionado == jugador) ? null : jugador;
    });
  }

  Future<void> _enviarVotos() async {
    if (_docIdActual == null) return;
    final elegido = _jugadorSeleccionado;
    if (elegido == null || elegido.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elegí un jugador antes de enviar tu voto.')),
      );
      return;
    }

    try {
      final aliasKey = _aliasLimpiada(widget.aliasUsuario);
      await _db
          .collection('votos_figura')
          .doc(_docIdActual)
          .update({
        if (_nombreTorneoStr.isNotEmpty) 'torneo': _nombreTorneoStr,
        'votos.$aliasKey': <String, int>{elegido: 1},
      });

      if (mounted) {
        setState(() => _yaVote = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Voto enviado para $elegido!'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  String _aliasLimpiada(String a) => a.replaceAll('.', '').trim();

  Widget _buildPodioFecha() {
    if (_docIdActual == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: _db
          .collection('votos_figura')
          .doc(_docIdActual)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final votosMap = (data?['votos'] as Map<String, dynamic>?) ?? {};
        final Map<String, int> totales = {};

        for (final entry in votosMap.entries) {
          if (entry.value is! Map) continue;
          final rep = Map<String, dynamic>.from(entry.value as Map);
          for (final v in rep.entries) {
            final int pts =
                v.value is int ? v.value as int : int.tryParse('${v.value}') ?? 0;
            if (pts > 0) {
              totales[v.key] = (totales[v.key] ?? 0) + pts;
            }
          }
        }

        if (totales.isEmpty) return const SizedBox.shrink();

        final ranking = totales.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final top3 = ranking.take(3).toList();

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.emoji_events,
                          size: 16, color: Colors.cyanAccent),
                      SizedBox(width: 6),
                      Text(
                        'Ranking de la fecha',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${votosMap.length} ${votosMap.length == 1 ? 'voto' : 'votos'}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...top3.asMap().entries.map((item) {
                final pos = item.key + 1;
                final jug = item.value.key;
                final pts = item.value.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '#$pos  $jug',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              pos == 1 ? FontWeight.bold : FontWeight.normal,
                          color: pos == 1 ? Colors.white : Colors.white70,
                        ),
                      ),
                      Text(
                        '$pts ${pts == 1 ? 'voto' : 'votos'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: pos == 1 ? Colors.amberAccent : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_fechaPartidoStr.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            _mensajeEspera.isNotEmpty
                ? _mensajeEspera
                : 'No hay partido disponible para votar todavía.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: Colors.amberAccent.withValues(alpha: 0.1),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.stars, color: Colors.amberAccent, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Fecha: $_fechaPartidoStr',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _yaVote
                    ? '¡Ya enviaste tu voto para esta fecha!'
                    : (_jugadorSeleccionado != null
                        ? 'Elegido: $_jugadorSeleccionado'
                        : 'Elegí a 1 jugador como figura de la fecha'),
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (_yaVote && _votacionAbierta) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.lightBlueAccent,
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  ),
                  icon: const Icon(Icons.edit, size: 15),
                  label: const Text(
                    'Modificar mi voto',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => setState(() => _yaVote = false),
                ),
              ],
            ],
          ),
        ),
        if (_yaVote || !_votacionAbierta) _buildPodioFecha(),
        Expanded(
          child: ListView.builder(
            itemCount: _jugadores.length,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            itemBuilder: (context, index) {
              final nombre = _jugadores[index];
              if (sonElMismoJugador(nombre, widget.aliasUsuario)) {
                return const SizedBox.shrink();
              }
              final bool esElegido = _jugadorSeleccionado != null &&
                  sonElMismoJugador(nombre, _jugadorSeleccionado!);

              return Card(
                color: esElegido
                    ? Colors.amberAccent.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: esElegido
                      ? const BorderSide(color: Colors.amberAccent, width: 1.2)
                      : BorderSide.none,
                ),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  onTap: (!_yaVote && _votacionAbierta)
                      ? () => _seleccionarJugador(nombre)
                      : null,
                  title: Text(
                    nombre,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: esElegido ? Colors.amberAccent : Colors.white,
                    ),
                  ),
                  trailing: _yaVote || !_votacionAbierta
                      ? (esElegido
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star,
                                      size: 14, color: Colors.black),
                                  SizedBox(width: 4),
                                  Text(
                                    'Tu voto',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink())
                      : Icon(
                          esElegido
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: esElegido ? Colors.amberAccent : Colors.grey,
                        ),
                ),
              );
            },
          ),
        ),
        if (!_yaVote && _votacionAbierta)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      _jugadorSeleccionado != null ? _enviarVotos : null,
                  icon: const Icon(Icons.send),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  label: const Text(
                    'Enviar mi voto',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
