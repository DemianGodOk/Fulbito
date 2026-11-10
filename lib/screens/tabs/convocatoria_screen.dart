import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants.dart';
import '../../models/jugador.dart';

class ConvocatoriaScreen extends StatefulWidget {
  final String nombreJugador;
  final String emailJugador;
  final Map<String, dynamic> infoPartido;
  final bool esAdmin;
  final bool esBaneado;
  final List<Jugador> titulares;
  final List<Jugador> suplentes;

  const ConvocatoriaScreen({
    super.key,
    required this.nombreJugador,
    required this.emailJugador,
    required this.infoPartido,
    required this.esAdmin,
    required this.esBaneado,
    required this.titulares,
    required this.suplentes,
  });

  @override
  State<ConvocatoriaScreen> createState() => _ConvocatoriaScreenState();
}

class _ConvocatoriaScreenState extends State<ConvocatoriaScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _cambiarEstadoJugador(Jugador j, String nuevoEstado) async {
    try {
      await _db.collection('partidos').doc('actual').update({
        'asistencia.${j.nombre}': nuevoEstado,
        'alertaCambioAsistencia': {
          'tipo': nuevoEstado,
          'nombre': j.nombre,
          'timestamp': FieldValue.serverTimestamp(),
        },
        if (nuevoEstado == 'baja')
          'ultimaAlerta': {
            'tipo': 'baja',
            'nombre': j.nombre,
            'timestamp': FieldValue.serverTimestamp(),
          },
      });
    } catch (e) {
      await _db.collection('partidos').doc('actual').set({
        'asistencia': {j.nombre: nuevoEstado},
      }, SetOptions(merge: true));
    }
  }

  Future<void> _enviarWhatsApp(String telefono, String nombre) async {
    final celLimpio = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    if (celLimpio.isEmpty) return;

    String celFinal = celLimpio;
    if (!celFinal.startsWith('54')) {
      if (celFinal.startsWith('9')) {
        celFinal = '54$celFinal';
      } else {
        celFinal = '549$celFinal';
      }
    }

    const mensaje = 'Recordatorio: No te olvides de confirmar asistencia del fulbito!';
    final url = Uri.parse('https://wa.me/$celFinal?text=${Uri.encodeComponent(mensaje)}');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir WhatsApp.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Widget _buildBotonAdmin(Jugador j, String estadoActual) {
    if (!widget.esAdmin) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (estadoActual != 'confirmado')
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.check_circle, size: 19, color: Colors.greenAccent),
            tooltip: 'Confirmar a ${j.nombre}',
            onPressed: () => _cambiarEstadoJugador(j, 'confirmado'),
          ),
        if (estadoActual != 'baja') ...[
          const SizedBox(width: 8),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.cancel, size: 19, color: Colors.redAccent),
            tooltip: 'Dar de baja a ${j.nombre}',
            onPressed: () => _cambiarEstadoJugador(j, 'baja'),
          ),
        ],
        if (estadoActual == 'pendiente' && j.telefono.trim().isNotEmpty) ...[
          const SizedBox(width: 8),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.chat_outlined, size: 19, color: Colors.green),
            tooltip: 'Avisar por WhatsApp',
            onPressed: () => _enviarWhatsApp(j.telefono, j.nombre),
          ),
        ],
      ],
    );
  }

  String _obtenerEstadoDeMapa(String nombre, Map<String, dynamic> asistencia) {
    for (final k in asistencia.keys) {
      if (sonElMismoJugador(k, nombre)) {
        return asistencia[k]?.toString() ?? 'pendiente';
      }
    }
    return 'pendiente';
  }

  @override
  Widget build(BuildContext context) {
    final nombreTorneo = (widget.infoPartido['nombreTorneo'] ?? kNombreTorneo).toString();
    final dia = widget.infoPartido['dia'] ?? 'Viernes 30 de Octubre';
    final hora = widget.infoPartido['hora'] ?? '20:00 hs';
    final lugar = widget.infoPartido['lugar'] ?? 'Estación 98 - Cancha 2';
    final mapsUrl = (widget.infoPartido['mapsUrl'] ?? '').toString().trim();
    final cupoMaximo = widget.infoPartido['cupoMaximo'] ?? 10;
    final Map<String, dynamic> asistencia =
        (widget.infoPartido['asistencia'] as Map<String, dynamic>?) ?? {};

    final int? inicioTorneoMillis = widget.infoPartido['fechaInicioTorneoMillis'] as int?;
    final int? finTorneoMillis = widget.infoPartido['fechaFinTorneoMillis'] as int?;

    int totalFechas = 0;
    if (inicioTorneoMillis != null && finTorneoMillis != null) {
      final dtInicio = DateTime.fromMillisecondsSinceEpoch(inicioTorneoMillis);
      final dtFin = DateTime.fromMillisecondsSinceEpoch(finTorneoMillis);
      final int dias = dtFin.difference(dtInicio).inDays;
      if (dias >= 0) {
        totalFechas = (dias / 7).round() + 1;
      }
    }

    final List<Jugador> prioritarios = widget.titulares.take(cupoMaximo).toList();
    final List<Jugador> colaEspera = [
      ...widget.titulares.skip(cupoMaximo),
      ...widget.suplentes,
    ];

    final List<Jugador> prioritariosConfirmados = [];
    final List<Jugador> prioritariosPendientes = [];
    final List<Jugador> prioritariosBajas = [];

    for (final j in prioritarios) {
      final String estado = _obtenerEstadoDeMapa(j.nombre, asistencia);
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

    for (final j in colaEspera) {
      final String estado = _obtenerEstadoDeMapa(j.nombre, asistencia);
      if (estado == 'confirmado') {
        colaConfirmados.add(j);
      } else if (estado == 'baja') {
        colaBajas.add(j);
      } else {
        colaPendientes.add(j);
      }
    }

    final List<Jugador> ascendidosDeCola =
        colaConfirmados.take(cuposLiberadosParaCola).toList();
    final List<Jugador> enEsperaConfirmados =
        colaConfirmados.skip(cuposLiberadosParaCola).toList();

    final List<Jugador> titularesConfirmados = [
      ...prioritariosConfirmados,
      ...ascendidosDeCola,
    ];

    final List<Jugador> bajas = [...prioritariosBajas, ...colaBajas];
    final List<Jugador> pendientes = [...prioritariosPendientes, ...colaPendientes];

    final String miEstado = _obtenerEstadoDeMapa(widget.nombreJugador, asistencia);
    final int totalTitulares = titularesConfirmados.length;
    final jugadorActualObj =
        Jugador(nombre: widget.nombreJugador, email: widget.emailJugador);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('historial_partidos').snapshots(),
      builder: (context, snapHistorial) {
        final docsHistorial = snapHistorial.data?.docs ?? [];
        final int nroFechaCalculada = docsHistorial.length + 1;
        String tituloFecha = 'Fecha $nroFechaCalculada';
        if (totalFechas > 0) {
          tituloFecha = 'Fecha $nroFechaCalculada de $totalFechas';
        }

        String campeon = '';
        bool torneoTerminado = false;

        if (finTorneoMillis != null && docsHistorial.isNotEmpty) {
          final hoyMillis = DateTime.now().millisecondsSinceEpoch;
          final bool hayPartidoFinalCargado = docsHistorial.any((d) {
            final data = d.data() as Map<String, dynamic>;
            final ts = (data['creadoEn'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return ts >= finTorneoMillis;
          });

          if (hayPartidoFinalCargado || hoyMillis >= finTorneoMillis) {
            torneoTerminado = true;

            final Map<String, int> ptsMap = {};
            final Map<String, int> pjMap = {};
            for (final d in docsHistorial) {
              final data = d.data() as Map<String, dynamic>;
              final int gA = data['equipoA_goles'] ?? 0;
              final int gB = data['equipoB_goles'] ?? 0;
              final List eqA = data['equipoA_jugadores'] ?? [];
              final List eqB = data['equipoB_jugadores'] ?? [];

              for (var j in eqA) {
                final nom = limpiarNombre(j.toString());
                if (nom.isEmpty) continue;
                pjMap[nom] = (pjMap[nom] ?? 0) + 1;
                ptsMap[nom] = (ptsMap[nom] ?? 0) + (gA > gB ? 3 : (gA == gB ? 1 : 0));
              }
              for (var j in eqB) {
                final nom = limpiarNombre(j.toString());
                if (nom.isEmpty) continue;
                pjMap[nom] = (pjMap[nom] ?? 0) + 1;
                ptsMap[nom] = (ptsMap[nom] ?? 0) + (gB > gA ? 3 : (gA == gB ? 1 : 0));
              }
            }

            final ranking = ptsMap.entries.toList()
              ..sort((a, b) {
                int cmp = b.value.compareTo(a.value);
                if (cmp != 0) return cmp;
                double promA = a.value / (pjMap[a.key] ?? 1);
                double promB = b.value / (pjMap[b.key] ?? 1);
                return promB.compareTo(promA);
              });

            if (ranking.isNotEmpty) {
              campeon = ranking.first.key;
            }
          }
        }

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
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              nombreTorneo,
                              style: const TextStyle(
                                color: Colors.lightBlueAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (torneoTerminado && campeon.isNotEmpty)
                            Text(
                              '🏆 ${campeon.toUpperCase()} CAMPEÓN',
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 0.5,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.lightBlueAccent.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tituloFecha,
                                    style: TextStyle(
                                      color: Colors.tealAccent.withValues(alpha: 0.9),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    dia,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 52,
                              color: Colors.white.withValues(alpha: 0.12),
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Horario',
                                  style: TextStyle(
                                    color: Colors.tealAccent.withValues(alpha: 0.8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hora,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.red),
                          const SizedBox(width: 4),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                if (mapsUrl.isEmpty) return;
                                final uri = Uri.tryParse(mapsUrl);
                                if (uri == null) return;
                                if (!await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                )) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('No se pudo abrir Google Maps.'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Text(
                                lugar,
                                style: const TextStyle(color: Colors.grey),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Cupos confirmados asegurados:',
                            style: TextStyle(fontSize: 13),
                          ),
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
                        valueColor: AlwaysStoppedAnimation<Color>(
                          totalTitulares >= cupoMaximo
                              ? Colors.lightBlueAccent
                              : Colors.orangeAccent,
                        ),
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
                      const Text(
                        '¿Jugás esta semana?',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      if (widget.esBaneado)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          child: const Text(
                            'Usuario restringido para confirmar convocatoria.',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _cambiarEstadoJugador(jugadorActualObj, 'confirmado'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: miEstado == 'confirmado'
                                      ? const Color(0xFF1B5E20)
                                      : Colors.grey.shade800,
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
                                    color: miEstado == 'baja' ? Colors.redAccent : Colors.grey.shade700,
                                  ),
                                ),
                                icon: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: miEstado == 'baja' ? Colors.redAccent : Colors.grey,
                                ),
                                label: Text(
                                  'Me bajo',
                                  style: TextStyle(
                                    color: miEstado == 'baja' ? Colors.redAccent : Colors.grey,
                                  ),
                                ),
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
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.greenAccent,
                      ),
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
                  child: Text(
                    'Aún no hay jugadores asegurados.',
                    style: TextStyle(color: Colors.grey),
                  ),
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
                      key: ValueKey(j.nombre),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: Colors.white.withValues(alpha: 0.03),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.green.shade800,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                j.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: esYo ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (esYo) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Tú',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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
                                Text(
                                  'Juega',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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
                    const Text(
                      'En Espera (Confirmaron)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.orangeAccent,
                      ),
                    ),
                    Text(
                      '${enEsperaConfirmados.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
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
                      key: ValueKey(j.nombre),
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
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                j.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (esYo) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Tú',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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
                                fontSize: 11,
                                color: Colors.orangeAccent,
                                fontWeight: FontWeight.bold,
                              ),
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
                    const Text(
                      'Sin Responder / Pendientes',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      '${pendientes.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
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
                        widget.titulares.skip(cupoMaximo).any(
                              (t) => sonElMismoJugador(t.nombre, j.nombre),
                            );

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
                      key: ValueKey(j.nombre),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: Colors.white.withValues(alpha: 0.02),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          icono,
                          size: 18,
                          color: colorSubtitulo,
                        ),
                        title: Text(
                          j.nombre,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        subtitle: Text(
                          subtitulo,
                          style: TextStyle(fontSize: 10, color: colorSubtitulo),
                        ),
                        trailing: _buildBotonAdmin(j, 'pendiente'),
                      ),
                    );
                  },
                ),
              ],
              if (bajas.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'No juegan (${bajas.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: bajas.length,
                  itemBuilder: (context, index) {
                    final j = bajas[index];
                    return Card(
                      key: ValueKey(j.nombre),
                      color: Colors.white.withValues(alpha: 0.03),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_off_outlined, color: Colors.grey, size: 18),
                        title: Text(
                          j.nombre,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Baja',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
      },
    );
  }
}
