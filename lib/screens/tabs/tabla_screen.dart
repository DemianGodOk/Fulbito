import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/jugador.dart';

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

  void _dialogoEditarVideo(BuildContext context, String docId, String actualUrl) {
    final urlCtrl = TextEditingController(text: actualUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.videocam, color: Colors.tealAccent),
            SizedBox(width: 8),
            Text('Link de Filmación', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: TextField(
          controller: urlCtrl,
          decoration: const InputDecoration(
            labelText: 'URL del video',
            hintText: 'https://youtube.com/... o Drive',
            prefixIcon: Icon(Icons.link, size: 18),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('historial_partidos')
                  .doc(docId)
                  .update({'videoUrl': urlCtrl.text.trim()});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _abrirVideo(BuildContext context, String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el enlace del video.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _mostrarDialogoCargarResultado(BuildContext context) async {
    final snapshotPartido =
        await FirebaseFirestore.instance.collection('partidos').doc('actual').get();
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
    final videoUrlCtrl = TextEditingController();

    final Map<String, int> asignaciones = {
      for (final j in jugadoresDisponibles) j: 0,
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF142030),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final equipoA =
              asignaciones.entries.where((e) => e.value == 1).map((e) => e.key).toList();
          final equipoB =
              asignaciones.entries.where((e) => e.value == 2).map((e) => e.key).toList();

          return Padding(
            padding: EdgeInsets.only(
              top: 20,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SafeArea(
              top: false,
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
                            Text(
                              'Cargar Resultado',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
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
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setModalState(() => fechaCtrl.text = formatearFechaEspanol(picked));
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Fecha del Partido',
                        prefixIcon: Icon(Icons.calendar_month, color: Colors.lightBlueAccent, size: 20),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: videoUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Link del video / filmación (opcional)',
                        hintText: 'https://youtube.com/... o Drive',
                        prefixIcon: Icon(Icons.videocam_outlined, color: Colors.tealAccent, size: 20),
                        isDense: true,
                      ),
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
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                ),
                              ),
                              TextField(
                                controller: golesACtrl,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.lightBlueAccent,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '0',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${equipoA.length} jugadores',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            'VS',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              TextField(
                                controller: nombreEquipoBCtrl,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                ),
                              ),
                              TextField(
                                controller: golesBCtrl,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orangeAccent,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '0',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${equipoB.length} jugadores',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Asignar Equipos (Blanco ➔ Negro ➔ Quitar)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
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
                            const SnackBar(
                              content: Text('Debes asignar jugadores a ambos equipos.'),
                            ),
                          );
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
                          'videoUrl': videoUrlCtrl.text.trim(),
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildVistaEstadisticas(List<QueryDocumentSnapshot<Object?>> docs) {
    if (docs.isEmpty) {
      return Card(
        color: Colors.white.withValues(alpha: 0.03),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(
            child: Text(
              'Aún no hay partidos cargados para calcular estadísticas.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    String canonicalizar(String raw) {
      final l = limpiarNombre(raw);
      final base = l.isNotEmpty ? l : raw.trim();
      for (final t in widget.titulares) {
        if (sonElMismoJugador(t.nombre, base)) {
          return t.nombre;
        }
      }
      return base;
    }

    final cronologicos = docs.reversed.toList();

    final Map<String, int> victoriasJuntos = {};
    final Map<String, int> derrotasJuntos = {};
    final Map<String, int> partidosJuntos = {};

    final Map<String, int> partidosEnfrentados = {};
    final Map<String, Map<String, int>> victoriasEnfrentados = {};
    final Map<String, int> empatesEnfrentados = {};

    final Map<String, int> rachaActual = {};
    final Map<String, int> rachaHistorica = {};

    for (final doc in cronologicos) {
      final data = doc.data() as Map<String, dynamic>;
      final int golesA = data['equipoA_goles'] ?? 0;
      final int golesB = data['equipoB_goles'] ?? 0;
      final List rawA = data['equipoA_jugadores'] ?? [];
      final List rawB = data['equipoB_jugadores'] ?? [];

      final List<String> teamA = rawA
          .map((j) => canonicalizar(j.toString()))
          .where((j) => j.isNotEmpty)
          .toSet()
          .toList();
      final List<String> teamB = rawB
          .map((j) => canonicalizar(j.toString()))
          .where((j) => j.isNotEmpty)
          .toSet()
          .toList();

      final bool ganaA = golesA > golesB;
      final bool ganaB = golesB > golesA;

      void procesarDuplas(List<String> eq, bool gano, bool perdio) {
        for (int i = 0; i < eq.length; i++) {
          for (int j = i + 1; j < eq.length; j++) {
            final par = [eq[i], eq[j]]..sort();
            final key = '${par[0]}___${par[1]}';
            partidosJuntos[key] = (partidosJuntos[key] ?? 0) + 1;
            if (gano) {
              victoriasJuntos[key] = (victoriasJuntos[key] ?? 0) + 1;
            } else if (perdio) {
              derrotasJuntos[key] = (derrotasJuntos[key] ?? 0) + 1;
            }
          }
        }
      }

      procesarDuplas(teamA, ganaA, ganaB);
      procesarDuplas(teamB, ganaB, ganaA);

      for (final pA in teamA) {
        for (final pB in teamB) {
          if (pA == pB) continue;
          final par = [pA, pB]..sort();
          final key = '${par[0]}___${par[1]}';
          partidosEnfrentados[key] = (partidosEnfrentados[key] ?? 0) + 1;
          victoriasEnfrentados.putIfAbsent(key, () => {par[0]: 0, par[1]: 0});

          if (ganaA) {
            victoriasEnfrentados[key]![pA] =
                (victoriasEnfrentados[key]![pA] ?? 0) + 1;
          } else if (ganaB) {
            victoriasEnfrentados[key]![pB] =
                (victoriasEnfrentados[key]![pB] ?? 0) + 1;
          } else {
            empatesEnfrentados[key] = (empatesEnfrentados[key] ?? 0) + 1;
          }
        }
      }

      final participantes = {...teamA, ...teamB};
      for (final p in participantes) {
        final enA = teamA.contains(p);
        final gano = enA ? ganaA : ganaB;

        if (gano) {
          rachaActual[p] = (rachaActual[p] ?? 0) + 1;
          if ((rachaActual[p] ?? 0) > (rachaHistorica[p] ?? 0)) {
            rachaHistorica[p] = rachaActual[p] ?? 0;
          }
        } else {
          rachaActual[p] = 0;
        }
      }
    }

    String? mejorDuplaP1, mejorDuplaP2;
    int mejorDuplaVictorias = 0;
    int mejorDuplaTotal = 0;
    for (final entry in victoriasJuntos.entries) {
      if (entry.value > mejorDuplaVictorias) {
        mejorDuplaVictorias = entry.value;
        final partes = entry.key.split('___');
        mejorDuplaP1 = partes[0];
        mejorDuplaP2 = partes[1];
        mejorDuplaTotal = partidosJuntos[entry.key] ?? entry.value;
      }
    }

    String? peorDuplaP1, peorDuplaP2;
    int peorDuplaDerrotas = 0;
    int peorDuplaTotal = 0;
    for (final entry in derrotasJuntos.entries) {
      if (entry.value > peorDuplaDerrotas) {
        peorDuplaDerrotas = entry.value;
        final partes = entry.key.split('___');
        peorDuplaP1 = partes[0];
        peorDuplaP2 = partes[1];
        peorDuplaTotal = partidosJuntos[entry.key] ?? entry.value;
      }
    }

    String? rivalP1, rivalP2;
    int maxEnfrentamientos = 0;
    int rivalWins1 = 0;
    int rivalWins2 = 0;
    int rivalEmpates = 0;
    for (final entry in partidosEnfrentados.entries) {
      if (entry.value > maxEnfrentamientos) {
        maxEnfrentamientos = entry.value;
        final partes = entry.key.split('___');
        rivalP1 = partes[0];
        rivalP2 = partes[1];
        final mapWins = victoriasEnfrentados[entry.key] ?? {};
        rivalWins1 = mapWins[rivalP1] ?? 0;
        rivalWins2 = mapWins[rivalP2] ?? 0;
        rivalEmpates = empatesEnfrentados[entry.key] ?? 0;
      }
    }

    String? rachaJugador;
    int maxRacha = 0;
    for (final entry in rachaHistorica.entries) {
      if (entry.value > maxRacha) {
        maxRacha = entry.value;
        rachaJugador = entry.key;
      }
    }

    Widget buildStatCard({
      required IconData icon,
      required Color iconColor,
      required String titulo,
      required String nombrePrincipal,
      required String detalle,
      String? subdetalle,
    }) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: const Color(0xFF16253B),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: iconColor,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nombrePrincipal,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    if (subdetalle != null && subdetalle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subdetalle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        buildStatCard(
          icon: Icons.star_rounded,
          iconColor: Colors.tealAccent,
          titulo: 'La mejor dupla',
          nombrePrincipal: mejorDuplaP1 != null
              ? '$mejorDuplaP1 & $mejorDuplaP2'
              : 'Sin datos suficientes',
          detalle: mejorDuplaP1 != null
              ? '$mejorDuplaVictorias victorias ($mejorDuplaTotal partidos juntos)'
              : 'Se necesitan victorias en equipo para calcular',
        ),
        buildStatCard(
          icon: Icons.heart_broken_outlined,
          iconColor: Colors.redAccent,
          titulo: 'La peor dupla',
          nombrePrincipal: peorDuplaP1 != null
              ? '$peorDuplaP1 & $peorDuplaP2'
              : 'Sin datos suficientes',
          detalle: peorDuplaP1 != null
              ? '$peorDuplaDerrotas derrotas ($peorDuplaTotal partidos juntos)'
              : 'Se necesitan derrotas en equipo para calcular',
        ),
        buildStatCard(
          icon: Icons.compare_arrows_rounded,
          iconColor: Colors.orangeAccent,
          titulo: 'Rivales clásicos',
          nombrePrincipal: rivalP1 != null
              ? '$rivalP1 vs $rivalP2'
              : 'Sin datos suficientes',
          detalle: rivalP1 != null
              ? '$maxEnfrentamientos partidos cara a cara'
              : 'Se necesitan enfrentamientos cruzados para calcular',
          subdetalle: rivalP1 != null
              ? '$rivalP1: $rivalWins1 vict. | $rivalP2: $rivalWins2 vict. | Empates: $rivalEmpates'
              : null,
        ),
        buildStatCard(
          icon: Icons.local_fire_department_rounded,
          iconColor: Colors.amberAccent,
          titulo: 'Racha Histórica',
          nombrePrincipal: rachaJugador ?? 'Sin datos suficientes',
          detalle: rachaJugador != null
              ? '$maxRacha victorias consecutivas'
              : 'Se necesitan partidos ganados para calcular',
        ),
        const SizedBox(height: 80),
      ],
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
        final Map<String, Map<String, dynamic>> stats = {};

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final int golesA = data['equipoA_goles'] ?? 0;
          final int golesB = data['equipoB_goles'] ?? 0;
          final List eqA = data['equipoA_jugadores'] ?? [];
          final List eqB = data['equipoB_jugadores'] ?? [];

          final bool ganaA = golesA > golesB;
          final bool ganaB = golesB > golesA;
          final bool empate = golesA == golesB;

          void registrar(
            String jugadorRaw,
            bool gano,
            bool empato,
            bool perdio,
            int gf,
            int gc,
          ) {
            final l = limpiarNombre(jugadorRaw);
            final jugador = l.isNotEmpty ? l : jugadorRaw.trim();
            if (jugador.isEmpty) return;

            stats.putIfAbsent(
              jugador,
              () => {'pj': 0, 'pg': 0, 'pe': 0, 'pp': 0, 'pts': 0, 'gf': 0, 'gc': 0},
            );
            stats[jugador]!['pj'] = (stats[jugador]!['pj'] as int) + 1;
            stats[jugador]!['gf'] = (stats[jugador]!['gf'] as int) + gf;
            stats[jugador]!['gc'] = (stats[jugador]!['gc'] as int) + gc;
            if (gano) {
              stats[jugador]!['pg'] = (stats[jugador]!['pg'] as int) + 1;
              stats[jugador]!['pts'] = (stats[jugador]!['pts'] as int) + 3;
            } else if (empato) {
              stats[jugador]!['pe'] = (stats[jugador]!['pe'] as int) + 1;
              stats[jugador]!['pts'] = (stats[jugador]!['pts'] as int) + 1;
            } else if (perdio) {
              stats[jugador]!['pp'] = (stats[jugador]!['pp'] as int) + 1;
            }
          }

          for (final j in eqA) {
            registrar(j.toString(), ganaA, empate, ganaB, golesA, golesB);
          }
          for (final j in eqB) {
            registrar(j.toString(), ganaB, empate, ganaA, golesB, golesA);
          }
        }

        final listaRanking = stats.entries.map((entry) {
          final data = Map<String, dynamic>.from(entry.value);
          final int pj = data['pj'] as int;
          final int puntos = data['pts'] as int;
          final double promedio = pj > 0 ? (puntos / pj).toDouble() : 0.0;
          data['promedio'] = promedio;
          return MapEntry(entry.key, data);
        }).toList()
          ..sort((a, b) {
            final int cmpPts = (b.value['pts'] as int).compareTo(a.value['pts'] as int);
            if (cmpPts != 0) return cmpPts;

            final double promedioA = (a.value['promedio'] as double?) ?? 0.0;
            final double promedioB = (b.value['promedio'] as double?) ?? 0.0;
            final int cmpProm = promedioB.compareTo(promedioA);
            if (cmpProm != 0) return cmpProm;

            final int cmpPJ = (a.value['pj'] as int).compareTo(b.value['pj'] as int);
            return cmpPJ;
          });

        return Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      {'id': 0, 'label': 'Posiciones', 'icon': Icons.format_list_numbered, 'flex': 11},
                      {'id': 1, 'label': 'Partidos', 'icon': Icons.history, 'flex': 10},
                      {'id': 2, 'label': 'Estadísticas', 'icon': Icons.query_stats, 'flex': 14},
                    ].map((tab) {
                      final int id = tab['id'] as int;
                      final bool seleccionado = _vistaSeleccionada == id;
                      return Expanded(
                        flex: tab['flex'] as int,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() => _vistaSeleccionada = id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            decoration: BoxDecoration(
                              color: seleccionado
                                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    tab['icon'] as IconData,
                                    size: 15,
                                    color: seleccionado ? Colors.lightBlueAccent : Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    tab['label'] as String,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
                                      color: seleccionado ? Colors.white : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                if (_vistaSeleccionada == 0) ...[
                  if (listaRanking.isEmpty)
                    Card(
                      color: Colors.white.withValues(alpha: 0.03),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                          child: Text(
                            'Aún no hay partidos cargados.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text(
                              '#',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Jugador',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              'PJ',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              'PG',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              'PE',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              'PP',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: Text(
                              'PTS',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.lightBlueAccent,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              'PROM',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.tealAccent,
                              ),
                            ),
                          ),
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

                        final int pj = data['pj'] as int;
                        final double promedio = (data['promedio'] as double?) ?? 0.0;
                        final String promedioTexto = promedio.toStringAsFixed(2);

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
                                  child: Text(
                                    nombre,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: esYo ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '$pj',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '${data['pg']}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 13, color: Colors.tealAccent),
                                  ),
                                ),
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '${data['pe']}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                                  ),
                                ),
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '${data['pp']}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 13, color: Colors.redAccent),
                                  ),
                                ),
                                SizedBox(
                                  width: 36,
                                  child: Text(
                                    '${data['pts']}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.lightBlueAccent,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    promedioTexto,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.tealAccent,
                                    ),
                                  ),
                                ),
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
                        child: Text(
                          'No hay partidos en el historial.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
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
                        final String videoUrl = (data['videoUrl'] ?? '').toString().trim();

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
                                    Row(
                                      children: [
                                        Text(
                                          fecha,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.lightBlueAccent,
                                          ),
                                        ),
                                        if (videoUrl.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          const Icon(Icons.videocam, color: Colors.tealAccent, size: 16),
                                        ],
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (widget.esAdmin) ...[
                                          IconButton(
                                            icon: Icon(
                                              videoUrl.isNotEmpty ? Icons.video_library : Icons.add_link,
                                              size: 18,
                                              color: Colors.tealAccent,
                                            ),
                                            tooltip: videoUrl.isNotEmpty ? 'Editar link del video' : 'Agregar link del video',
                                            onPressed: () => _dialogoEditarVideo(context, docId, videoUrl),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline,
                                                size: 18, color: Colors.redAccent),
                                            tooltip: 'Borrar partido',
                                            onPressed: () async =>
                                                await FirebaseFirestore.instance
                                                    .collection('historial_partidos')
                                                    .doc(docId)
                                                    .delete(),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        children: [
                                          Text(
                                            eqA,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$golesA',
                                            style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.lightBlueAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Text(
                                      'vs',
                                      style: TextStyle(fontSize: 16, color: Colors.grey),
                                    ),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          Text(
                                            eqB,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$golesB',
                                            style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orangeAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        jugsA.map((j) => limpiarNombre(j.toString())).join(', '),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white60,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        jugsB.map((j) => limpiarNombre(j.toString())).join(', '),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white60,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                                if (videoUrl.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.tealAccent,
                                        side: BorderSide(color: Colors.tealAccent.withValues(alpha: 0.5)),
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                      ),
                                      icon: const Icon(Icons.play_circle_fill, size: 18),
                                      label: const Text(
                                        'Ver filmación del partido',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      onPressed: () => _abrirVideo(context, videoUrl),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],

                if (_vistaSeleccionada == 2) ...[
                  _buildVistaEstadisticas(docs),
                ],

                const SizedBox(height: 80),
              ],
            ),
          ),
          floatingActionButton: (_vistaSeleccionada == 1 && widget.puedeCargarResultado)
              ? FloatingActionButton.extended(
                  onPressed: () => _mostrarDialogoCargarResultado(context),
                  backgroundColor: Colors.lightBlueAccent,
                  foregroundColor: Colors.black,
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'Cargar Resultado',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                )
              : null,
        );
      },
    );
  }
}
