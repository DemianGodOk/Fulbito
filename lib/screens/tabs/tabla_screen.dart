import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/jugador.dart';

class TablaScreen extends StatefulWidget {
  final bool esAdmin;
  final bool puedeCargarResultado;
  final String nombreJugador;
  final List<Jugador> titulares;
  final List<Jugador> suplentes;
  final String nombreTorneoActual;
  final List<String> historialTorneos;
  final bool registrarTantos;

  const TablaScreen({
    super.key,
    required this.esAdmin,
    required this.puedeCargarResultado,
    required this.nombreJugador,
    required this.titulares,
    required this.suplentes,
    this.nombreTorneoActual = '',
    this.historialTorneos = const [],
    this.registrarTantos = false,
  });

  @override
  State<TablaScreen> createState() => _TablaScreenState();
}

class _TablaScreenState extends State<TablaScreen> {
  int _vistaSeleccionada = 0;
  String? _torneoSeleccionado;
  // 0 = Actual (torneo seleccionado), 1 = Anual (año actual), 2 = Histórico (todos los años)
  int _alcanceFiltro = 0;

  late Stream<QuerySnapshot> _streamHistorial;
  late Stream<QuerySnapshot> _streamVotosFigura;

  List<String> _obtenerTorneosOrdenados([Iterable<String> extraTorneos = const []]) {
    final setUnicos = <String>{};
    if (widget.nombreTorneoActual.trim().isNotEmpty) {
      setUnicos.add(widget.nombreTorneoActual.trim());
    }
    for (final t in widget.historialTorneos) {
      if (t.trim().isNotEmpty) setUnicos.add(t.trim());
    }
    for (final t in extraTorneos) {
      if (t.trim().isNotEmpty) setUnicos.add(t.trim());
    }

    int pesoTemporada(String nombre) {
      final low = nombre.toLowerCase();
      if (low.contains('clausura') || low.contains('final')) return 3;
      if (low.contains('apertura')) return 2;
      if (low.contains('verano')) return 1;
      return 0;
    }

    final lista = setUnicos.toList();
    lista.sort((a, b) {
      if (a == widget.nombreTorneoActual) return -1;
      if (b == widget.nombreTorneoActual) return 1;

      final anioA = _extraerAnioDeTorneo(a);
      final anioB = _extraerAnioDeTorneo(b);
      if (anioA != anioB) return anioB.compareTo(anioA);

      final pesoA = pesoTemporada(a);
      final pesoB = pesoTemporada(b);
      if (pesoA != pesoB) return pesoB.compareTo(pesoA);

      return b.compareTo(a);
    });
    return lista;
  }

  @override
  void initState() {
    super.initState();
    final ordenados = _obtenerTorneosOrdenados();
    _torneoSeleccionado = widget.nombreTorneoActual.isNotEmpty
        ? widget.nombreTorneoActual
        : (ordenados.isNotEmpty ? ordenados.first : '');
    _actualizarStream();
  }

  @override
  void didUpdateWidget(TablaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ordenados = _obtenerTorneosOrdenados();
    if (oldWidget.nombreTorneoActual != widget.nombreTorneoActual) {
      _torneoSeleccionado = widget.nombreTorneoActual;
    } else if (_torneoSeleccionado != null &&
        ordenados.isNotEmpty &&
        !ordenados.contains(_torneoSeleccionado)) {
      _torneoSeleccionado = ordenados.first;
    }
  }

  int _extraerAnioDeTorneo(String nombreTorneo) {
    final match = RegExp(r'(20\d{2})').firstMatch(nombreTorneo);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? DateTime.now().year;
    }
    return DateTime.now().year;
  }

  int _extraerAnioDeDocumento(Map<String, dynamic> data) {
    final String torneo = (data['torneo'] ?? '').toString();
    final matchTorneo = RegExp(r'(20\d{2})').firstMatch(torneo);
    if (matchTorneo != null) {
      return int.tryParse(matchTorneo.group(1)!) ?? DateTime.now().year;
    }
    final Timestamp? creadoEn = data['creadoEn'] as Timestamp?;
    if (creadoEn != null) {
      return creadoEn.toDate().year;
    }
    final String fecha =
        (data['fecha'] ?? data['fechaPartido'] ?? '').toString();
    final matchFecha = RegExp(r'(20\d{2})').firstMatch(fecha);
    if (matchFecha != null) {
      return int.tryParse(matchFecha.group(1)!) ?? DateTime.now().year;
    }
    return DateTime.now().year;
  }

  void _actualizarStream() {
    _streamHistorial =
        FirebaseFirestore.instance.collection('historial_partidos').snapshots();
    _streamVotosFigura =
        FirebaseFirestore.instance.collection('votos_figura').snapshots();
  }

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
    final snapshotPartido = await FirebaseFirestore.instance.collection('partidos').doc('actual').get();
    final Map<String, dynamic> asistenciaActiva =
        (snapshotPartido.data()?['asistencia'] as Map<String, dynamic>?) ?? {};
    final Map<String, dynamic> ultimaAsistencia =
        (snapshotPartido.data()?['ultimaAsistencia'] as Map<String, dynamic>?) ?? {};

    Map<String, dynamic> asistenciaUsar = asistenciaActiva;
    if (!asistenciaActiva.values.contains('confirmado') &&
        ultimaAsistencia.values.contains('confirmado')) {
      asistenciaUsar = ultimaAsistencia;
    }

    List<String> jugadoresConfirmados = asistenciaUsar.entries
        .where((e) => e.value == 'confirmado')
        .map((e) => e.key)
        .toList();

    List<String> todoElPlantel = [
      ...widget.titulares.map((t) => t.nombre),
      ...widget.suplentes.map((s) => s.nombre)
    ];
    todoElPlantel.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    jugadoresConfirmados.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    bool mostrarTodos = jugadoresConfirmados.isEmpty;
    List<String> jugadoresDisponibles =
        mostrarTodos ? todoElPlantel : List.from(jugadoresConfirmados);

    if (!context.mounted) return;

    final fechaCtrl = TextEditingController(text: formatearFechaEspanol(DateTime.now()));
    final golesACtrl = TextEditingController(text: '0');
    final golesBCtrl = TextEditingController(text: '0');
    final nombreEquipoACtrl = TextEditingController(text: 'Equipo Celeste');
    final nombreEquipoBCtrl = TextEditingController(text: 'Equipo Amarillo');
    final videoUrlCtrl = TextEditingController();

    // 0 = sin asignar, 1 = Equipo A (izquierda), 2 = Equipo B (derecha)
    final Map<String, int> asignaciones = {
      for (final j in todoElPlantel) j: 0,
    };
    final Map<String, int> tantosPorJugador = {
      for (final j in todoElPlantel) j: 0,
    };
    bool registrarTantosModal = widget.registrarTantos;

    int sumaTantosEquipo(int eq) {
      int total = 0;
      for (final entry in asignaciones.entries) {
        if (entry.value == eq) {
          total += tantosPorJugador[entry.key] ?? 0;
        }
      }
      return total;
    }

    void ajustarTantosJugador(
      StateSetter setModalState,
      String jugador,
      int equipoNum,
      int delta,
    ) {
      final int prevSuma = sumaTantosEquipo(equipoNum);
      final int actual = tantosPorJugador[jugador] ?? 0;
      final int nuevo = (actual + delta).clamp(0, 99);
      if (nuevo == actual) return;

      setModalState(() {
        tantosPorJugador[jugador] = nuevo;
        final int nuevaSuma = sumaTantosEquipo(equipoNum);
        final ctrl = equipoNum == 1 ? golesACtrl : golesBCtrl;
        final int marcadorActual = int.tryParse(ctrl.text.trim()) ?? 0;
        if (marcadorActual == prevSuma) {
          ctrl.text = '$nuevaSuma';
        }
      });
    }

    Widget buildColumnaEquipo({
      required StateSetter setModalState,
      required int equipoNum, // 1 = izquierda (Celeste), 2 = derecha (Amarillo)
      required String tituloEquipo,
      required Color colorEquipo,
    }) {
      final bool esIzquierda = equipoNum == 1;
      final int otroEquipo = esIzquierda ? 2 : 1;

      return Container(
        decoration: BoxDecoration(
          color: colorEquipo.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorEquipo.withValues(alpha: 0.25)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tituloEquipo,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorEquipo,
              ),
            ),
            const Divider(height: 12),
            if (jugadoresDisponibles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Sin jugadores',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              )
            else
              ...jugadoresDisponibles.map((jugador) {
                final int estado = asignaciones[jugador] ?? 0;
                final bool seleccionadoAqui = estado == equipoNum;
                final bool deshabilitado = estado == otroEquipo;
                final int tantos = tantosPorJugador[jugador] ?? 0;

                Widget buildContador() {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => ajustarTantosJugador(
                          setModalState,
                          jugador,
                          equipoNum,
                          -1,
                        ),
                        child: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '-',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 20,
                        child: Text(
                          '$tantos',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: tantos > 0 ? colorEquipo : Colors.white,
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => ajustarTantosJugador(
                          setModalState,
                          jugador,
                          equipoNum,
                          1,
                        ),
                        child: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorEquipo.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '+',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: colorEquipo,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                void toggleSeleccion() {
                  if (deshabilitado) return;
                  final int prevSuma = sumaTantosEquipo(equipoNum);
                  setModalState(() {
                    if (seleccionadoAqui) {
                      asignaciones[jugador] = 0;
                      tantosPorJugador[jugador] = 0;
                      final int nuevaSuma = sumaTantosEquipo(equipoNum);
                      final ctrl = equipoNum == 1 ? golesACtrl : golesBCtrl;
                      final int marcadorActual =
                          int.tryParse(ctrl.text.trim()) ?? 0;
                      if (marcadorActual == prevSuma) {
                        ctrl.text = '$nuevaSuma';
                      }
                    } else {
                      asignaciones[jugador] = equipoNum;
                    }
                  });
                }

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 2.5),
                  decoration: BoxDecoration(
                    color: seleccionadoAqui
                        ? colorEquipo.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: deshabilitado ? 0.01 : 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: seleccionadoAqui
                          ? colorEquipo.withValues(alpha: 0.65)
                          : Colors.transparent,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: deshabilitado ? null : toggleSeleccion,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 6,
                      ),
                      child: Row(
                        children: esIzquierda
                            ? [
                                if (!registrarTantosModal || !seleccionadoAqui) ...[
                                  Icon(
                                    seleccionadoAqui
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 14,
                                    color: deshabilitado
                                        ? Colors.white12
                                        : (seleccionadoAqui
                                            ? colorEquipo
                                            : Colors.white38),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Expanded(
                                  child: Text(
                                    jugador,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: seleccionadoAqui
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: deshabilitado
                                          ? Colors.white24
                                          : (seleccionadoAqui
                                              ? Colors.white
                                              : Colors.white70),
                                    ),
                                  ),
                                ),
                                if (registrarTantosModal && seleccionadoAqui) ...[
                                  const SizedBox(width: 4),
                                  buildContador(),
                                ],
                              ]
                            : [
                                if (registrarTantosModal && seleccionadoAqui) ...[
                                  buildContador(),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Text(
                                    jugador,
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: seleccionadoAqui
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: deshabilitado
                                          ? Colors.white24
                                          : (seleccionadoAqui
                                              ? Colors.white
                                              : Colors.white70),
                                    ),
                                  ),
                                ),
                                if (!registrarTantosModal || !seleccionadoAqui) ...[
                                  const SizedBox(width: 5),
                                  Icon(
                                    seleccionadoAqui
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 14,
                                    color: deshabilitado
                                        ? Colors.white12
                                        : (seleccionadoAqui
                                            ? colorEquipo
                                            : Colors.white38),
                                  ),
                                ],
                              ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      );
    }

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
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
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
                    const SizedBox(height: 10),
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
                    const SizedBox(height: 10),
                    TextField(
                      controller: videoUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Link del video / filmación (opcional)',
                        hintText: 'https://youtube.com/... o Drive',
                        prefixIcon: Icon(Icons.videocam_outlined, color: Colors.tealAccent, size: 20),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              TextField(
                                controller: nombreEquipoACtrl,
                                onChanged: (_) => setModalState(() {}),
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
                                onChanged: (_) => setModalState(() {}),
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
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setModalState(
                              () => registrarTantosModal = !registrarTantosModal),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: registrarTantosModal,
                                  activeColor: Colors.tealAccent,
                                  checkColor: Colors.black,
                                  onChanged: (v) => setModalState(
                                      () => registrarTantosModal = v ?? false),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Tantos',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.tealAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Mostrar todos',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            Switch(
                              value: mostrarTodos,
                              onChanged: (val) {
                                setModalState(() {
                                  mostrarTodos = val;
                                  if (mostrarTodos) {
                                    jugadoresDisponibles = todoElPlantel;
                                  } else {
                                    jugadoresDisponibles =
                                        List.from(jugadoresConfirmados);
                                    for (final key in asignaciones.keys.toList()) {
                                      if (!jugadoresDisponibles.contains(key)) {
                                        asignaciones[key] = 0;
                                        tantosPorJugador[key] = 0;
                                      }
                                    }
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: buildColumnaEquipo(
                            setModalState: setModalState,
                            equipoNum: 1,
                            tituloEquipo: nombreEquipoACtrl.text.trim().isNotEmpty
                                ? nombreEquipoACtrl.text.trim()
                                : 'Equipo Celeste',
                            colorEquipo: Colors.lightBlueAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: buildColumnaEquipo(
                            setModalState: setModalState,
                            equipoNum: 2,
                            tituloEquipo: nombreEquipoBCtrl.text.trim().isNotEmpty
                                ? nombreEquipoBCtrl.text.trim()
                                : 'Equipo Amarillo',
                            colorEquipo: Colors.orangeAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
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

                        final String torneoGuardar = (_alcanceFiltro == 0 &&
                                _torneoSeleccionado != null &&
                                _torneoSeleccionado!.isNotEmpty)
                            ? _torneoSeleccionado!
                            : widget.nombreTorneoActual;

                        final Map<String, int> tantosGuardar = {};
                        if (registrarTantosModal) {
                          for (final j in [...equipoA, ...equipoB]) {
                            final t = tantosPorJugador[j] ?? 0;
                            if (t > 0) {
                              tantosGuardar[j] = t;
                            }
                          }
                        }

                        await FirebaseFirestore.instance.collection('historial_partidos').add({
                          'torneo': torneoGuardar,
                          'fecha': fechaCtrl.text.trim(),
                          'equipoA_nombre': nombreEquipoACtrl.text.trim(),
                          'equipoB_nombre': nombreEquipoBCtrl.text.trim(),
                          'equipoA_goles': golesA,
                          'equipoB_goles': golesB,
                          'equipoA_jugadores': equipoA,
                          'equipoB_jugadores': equipoB,
                          if (tantosGuardar.isNotEmpty) 'tantos': tantosGuardar,
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

  void _abrirProgresoJugador(
    String nombreJugador,
    String tituloContextoActual,
    List<QueryDocumentSnapshot<Object?>> docsVistaActual,
    List<QueryDocumentSnapshot<Object?>> docsTodosLosTorneos, {
    bool hayVariosTorneos = true,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF142030),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ProgresoJugadorSheet(
        nombreJugador: nombreJugador,
        tituloVistaActual: tituloContextoActual,
        docsVistaActual: docsVistaActual,
        docsTodosLosTorneos: docsTodosLosTorneos,
        titulares: widget.titulares,
        suplentes: widget.suplentes,
        hayVariosTorneos: hayVariosTorneos,
      ),
    );
  }

  Widget _buildVistaEstadisticas(
    List<QueryDocumentSnapshot<Object?>> docs, {
    required int alcanceEfectivo,
    required String torneoRef,
    required int anioFiltro,
  }) {
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
      for (final t in [...widget.titulares, ...widget.suplentes]) {
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
    final Map<String, int> rachaDerrotasActual = {};
    final Map<String, int> rachaDerrotasHistorica = {};
    final Map<String, int> rachaSinGanarActual = {};
    final Map<String, int> rachaSinGanarHistorica = {};
    final Map<String, int> tantosTotales = {};

    for (final doc in cronologicos) {
      final data = doc.data() as Map<String, dynamic>;
      final int golesA = data['equipoA_goles'] ?? 0;
      final int golesB = data['equipoB_goles'] ?? 0;
      final List rawA = data['equipoA_jugadores'] ?? [];
      final List rawB = data['equipoB_jugadores'] ?? [];

      if (data['tantos'] is Map) {
        final rawTantos = Map<String, dynamic>.from(data['tantos'] as Map);
        for (final entry in rawTantos.entries) {
          final jug = canonicalizar(entry.key.toString());
          final int val = entry.value is int
              ? entry.value as int
              : int.tryParse('${entry.value}') ?? 0;
          if (jug.isNotEmpty && val > 0) {
            tantosTotales[jug] = (tantosTotales[jug] ?? 0) + val;
          }
        }
      }

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
        final perdio = enA ? ganaB : ganaA;

        if (gano) {
          rachaActual[p] = (rachaActual[p] ?? 0) + 1;
          if ((rachaActual[p] ?? 0) > (rachaHistorica[p] ?? 0)) {
            rachaHistorica[p] = rachaActual[p] ?? 0;
          }
          rachaSinGanarActual[p] = 0;
        } else {
          rachaActual[p] = 0;
          rachaSinGanarActual[p] = (rachaSinGanarActual[p] ?? 0) + 1;
          if ((rachaSinGanarActual[p] ?? 0) > (rachaSinGanarHistorica[p] ?? 0)) {
            rachaSinGanarHistorica[p] = rachaSinGanarActual[p] ?? 0;
          }
        }

        if (perdio) {
          rachaDerrotasActual[p] = (rachaDerrotasActual[p] ?? 0) + 1;
          if ((rachaDerrotasActual[p] ?? 0) > (rachaDerrotasHistorica[p] ?? 0)) {
            rachaDerrotasHistorica[p] = rachaDerrotasActual[p] ?? 0;
          }
        } else {
          rachaDerrotasActual[p] = 0;
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

    String? mufaJugador;
    int maxDerrotas = 0;
    for (final entry in rachaDerrotasHistorica.entries) {
      if (entry.value > maxDerrotas) {
        maxDerrotas = entry.value;
        mufaJugador = entry.key;
      }
    }

    String? mufaSubdetalle;
    if (mufaJugador != null) {
      final int maxSinGanarMufa = rachaSinGanarHistorica[mufaJugador] ?? maxDerrotas;
      final bool vigente = (rachaDerrotasActual[mufaJugador] ?? 0) == maxDerrotas;
      final List<String> notas = [];
      if (vigente) notas.add('Racha vigente');
      if (maxSinGanarMufa > maxDerrotas) {
        notas.add('Llegó a $maxSinGanarMufa seguidos sin ganar');
      }
      if (notas.isNotEmpty) {
        mufaSubdetalle = notas.join(' • ');
      }
    }

    final rankingTantos = tantosTotales.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        if (cmp != 0) return cmp;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    final top3Tantos = rankingTantos.take(3).toList();

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

    Widget buildTop3TantosCard() {
      const Color accent = Colors.lightGreenAccent;
      final List<Color> coloresPodio = [
        Colors.amberAccent,
        Colors.lightBlueAccent,
        Colors.orangeAccent,
      ];

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
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.scoreboard_outlined,
                  color: accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOP 3 GOLEADORES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: accent,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (top3Tantos.isEmpty) ...[
                      const Text(
                        'Sin tantos registrados',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Activá "Tantos" al cargar un resultado para sumar',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ] else
                      ...List.generate(top3Tantos.length, (i) {
                        final entry = top3Tantos[i];
                        final colorPos = coloresPodio[i];
                        final int cant = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Row(
                            children: [
                              Container(
                                width: 22,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colorPos.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '${i + 1}°',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: colorPos,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Text(
                                '$cant ${cant == 1 ? 'tanto' : 'tantos'}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorPos,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
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
        buildStatCard(
          icon: Icons.sentiment_very_dissatisfied_rounded,
          iconColor: Colors.purpleAccent,
          titulo: 'El Mufa',
          nombrePrincipal: mufaJugador ?? 'Sin datos suficientes',
          detalle: mufaJugador != null
              ? '$maxDerrotas ${maxDerrotas == 1 ? 'derrota consecutiva' : 'derrotas consecutivas'}'
              : 'Se necesitan partidos perdidos para calcular',
          subdetalle: mufaSubdetalle,
        ),
        StreamBuilder<QuerySnapshot>(
          stream: _streamVotosFigura,
          builder: (context, snapVotos) {
            final allVotosDocs = snapVotos.data?.docs ?? [];
            final filteredVotosDocs = allVotosDocs.where((vDoc) {
              final vData = vDoc.data() as Map<String, dynamic>;
              if (alcanceEfectivo == 2) return true;
              if (alcanceEfectivo == 1) {
                return _extraerAnioDeDocumento(vData) == anioFiltro;
              }
              final t = (vData['torneo'] ?? '').toString().trim();
              if (t.isNotEmpty) {
                return t == torneoRef.trim();
              }
              return torneoRef.trim() == widget.nombreTorneoActual.trim();
            }).toList();

            final Map<String, int> puntosMvp = {};
            final Map<String, int> fechasVotado = {};

            for (final vDoc in filteredVotosDocs) {
              final vData = vDoc.data() as Map<String, dynamic>;
              final votosMap =
                  (vData['votos'] as Map<String, dynamic>?) ?? {};
              final Set<String> votadosEnEstaFecha = {};

              for (final entryVotante in votosMap.entries) {
                if (entryVotante.value is! Map) continue;
                final repartos =
                    Map<String, dynamic>.from(entryVotante.value as Map);
                for (final votoEntry in repartos.entries) {
                  final jug = canonicalizar(votoEntry.key.toString());
                  final int pts = votoEntry.value is int
                      ? votoEntry.value as int
                      : int.tryParse('${votoEntry.value}') ?? 0;
                  if (jug.isNotEmpty && pts > 0) {
                    puntosMvp[jug] = (puntosMvp[jug] ?? 0) + pts;
                    votadosEnEstaFecha.add(jug);
                  }
                }
              }

              for (final jug in votadosEnEstaFecha) {
                fechasVotado[jug] = (fechasVotado[jug] ?? 0) + 1;
              }
            }

            final rankingMvp = puntosMvp.entries.toList()
              ..sort((a, b) {
                final cmpPts = b.value.compareTo(a.value);
                if (cmpPts != 0) return cmpPts;
                return (fechasVotado[b.key] ?? 0)
                    .compareTo(fechasVotado[a.key] ?? 0);
              });

            final String tituloMvp = alcanceEfectivo == 2
                ? 'El MvP histórico'
                : (alcanceEfectivo == 1
                    ? 'El MvP del año'
                    : 'El MvP del torneo');

            if (rankingMvp.isEmpty) {
              return buildStatCard(
                icon: Icons.emoji_events_rounded,
                iconColor: Colors.cyanAccent,
                titulo: tituloMvp,
                nombrePrincipal: 'Sin votos registrados',
                detalle: 'Votá la figura en El Vestuario para sumar puntos',
              );
            }

            final int maxPtsMvp = rankingMvp.first.value;
            final lideres = rankingMvp
                .where((e) => e.value == maxPtsMvp)
                .map((e) => e.key)
                .toList();

            final String nombreMvp = lideres.join(' & ');
            final String detalleMvp = lideres.length > 1
                ? '$maxPtsMvp ${maxPtsMvp == 1 ? 'punto' : 'puntos'} c/u (empate)'
                : '$maxPtsMvp ${maxPtsMvp == 1 ? 'punto recibido' : 'puntos recibidos'}';

            final List<String> notasMvp = [];
            if (lideres.length == 1) {
              final int fCount = fechasVotado[lideres.first] ?? 1;
              notasMvp.add(
                  'Votado en $fCount ${fCount == 1 ? 'fecha' : 'fechas'}');
            }
            final segundo =
                rankingMvp.where((e) => e.value < maxPtsMvp).firstOrNull;
            if (segundo != null) {
              notasMvp.add('2°: ${segundo.key} (${segundo.value} pts)');
            }

            return buildStatCard(
              icon: Icons.emoji_events_rounded,
              iconColor: Colors.cyanAccent,
              titulo: tituloMvp,
              nombrePrincipal: nombreMvp,
              detalle: detalleMvp,
              subdetalle: notasMvp.isNotEmpty ? notasMvp.join(' • ') : null,
            );
          },
        ),
        if (widget.registrarTantos) buildTop3TantosCard(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _streamHistorial,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<QueryDocumentSnapshot<Object?>> todosDocs =
            snapshot.data?.docs.toList() ?? [];

        final torneosDeDocs = todosDocs
            .map((d) => ((d.data() as Map<String, dynamic>)['torneo'] ?? '').toString().trim())
            .where((t) => t.isNotEmpty);
        final torneosLista = _obtenerTorneosOrdenados(torneosDeDocs);
        final bool hayVariosTorneos = torneosLista.length > 1;
        final int alcanceEfectivo = hayVariosTorneos ? _alcanceFiltro : 0;
        final String torneoRef =
            (_torneoSeleccionado != null && torneosLista.contains(_torneoSeleccionado))
                ? _torneoSeleccionado!
                : (torneosLista.isNotEmpty ? torneosLista.first : widget.nombreTorneoActual);
        final int anioFiltro = _extraerAnioDeTorneo(torneoRef);

        todosDocs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final Timestamp? tA = aData['creadoEn'] as Timestamp?;
          final Timestamp? tB = bData['creadoEn'] as Timestamp?;
          if (tA == null && tB == null) return 0;
          if (tA == null) return 1;
          if (tB == null) return -1;
          return tB.compareTo(tA);
        });

        List<QueryDocumentSnapshot<Object?>> docs;
        if (alcanceEfectivo == 2) {
          docs = todosDocs;
        } else if (alcanceEfectivo == 1) {
          docs = todosDocs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return _extraerAnioDeDocumento(data) == anioFiltro;
          }).toList();
        } else {
          docs = todosDocs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final t = (data['torneo'] ?? '').toString().trim();
            return t == torneoRef.trim();
          }).toList();
        }

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
                if (hayVariosTorneos) ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final String textoSelector = alcanceEfectivo == 2
                          ? 'Histórico Completo'
                          : (alcanceEfectivo == 1
                              ? 'Torneos $anioFiltro'
                              : torneoRef);
                      final Color colorTextoSelector = alcanceEfectivo == 2
                          ? Colors.grey
                          : (alcanceEfectivo == 1
                              ? Colors.tealAccent
                              : Colors.white);
                      final Color colorIconoSelector = alcanceEfectivo == 2
                          ? Colors.grey
                          : (alcanceEfectivo == 1
                              ? Colors.tealAccent
                              : Colors.lightBlueAccent);

                      return PopupMenuButton<String>(
                        enabled: alcanceEfectivo != 2,
                        initialValue: torneoRef,
                        color: const Color(0xFF16253B),
                        elevation: 8,
                        offset: const Offset(0, 40),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                          maxWidth: constraints.maxWidth,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Colors.lightBlueAccent.withValues(alpha: 0.25),
                          ),
                        ),
                        onSelected: (String newValue) {
                          if (newValue != _torneoSeleccionado) {
                            setState(() {
                              _torneoSeleccionado = newValue;
                            });
                          }
                        },
                        itemBuilder: (BuildContext context) {
                          return torneosLista.map((String torneo) {
                            final bool esActual = torneo == torneoRef;
                            return PopupMenuItem<String>(
                              value: torneo,
                              height: 34,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      torneo,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: esActual
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        fontSize: 12.5,
                                        color: esActual
                                            ? Colors.lightBlueAccent
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                  if (esActual)
                                    const Icon(
                                      Icons.check,
                                      size: 15,
                                      color: Colors.lightBlueAccent,
                                    ),
                                ],
                              ),
                            );
                          }).toList();
                        },
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                                alpha: alcanceEfectivo == 2 ? 0.02 : 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: alcanceEfectivo == 2
                                  ? Colors.white12
                                  : (alcanceEfectivo == 1
                                      ? Colors.tealAccent.withValues(alpha: 0.35)
                                      : Colors.lightBlueAccent
                                          .withValues(alpha: 0.3)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  textoSelector,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: colorTextoSelector,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                                color: colorIconoSelector,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        {'id': 0, 'label': 'Actual', 'color': Colors.lightBlueAccent},
                        {'id': 1, 'label': 'Anual ($anioFiltro)', 'color': Colors.tealAccent},
                        {'id': 2, 'label': 'Histórico', 'color': Colors.amberAccent},
                      ].map((opt) {
                        final int id = opt['id'] as int;
                        final Color activeColor = opt['color'] as Color;
                        final bool seleccionado = alcanceEfectivo == id;
                        return Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => setState(() => _alcanceFiltro = id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                              decoration: BoxDecoration(
                                color: seleccionado
                                    ? activeColor.withValues(alpha: 0.22)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  opt['label'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
                                    color: seleccionado ? activeColor : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      {'id': 0, 'label': 'Posiciones', 'icon': Icons.format_list_numbered, 'flex': 11},
                      {'id': 1, 'label': 'Partidos (${docs.length})', 'icon': Icons.history, 'flex': 12},
                      {'id': 2, 'label': 'Estadísticas', 'icon': Icons.query_stats, 'flex': 13},
                    ].map((tab) {
                      final int id = tab['id'] as int;
                      final bool seleccionado = _vistaSeleccionada == id;
                      return Expanded(
                        flex: tab['flex'] as int,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: () => setState(() => _vistaSeleccionada = id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                            decoration: BoxDecoration(
                              color: seleccionado
                                  ? Colors.lightBlueAccent.withValues(alpha: 0.22)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(11),
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
                const SizedBox(height: 10),

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
                      padding: EdgeInsets.zero,
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
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _abrirProgresoJugador(
                              nombre,
                              alcanceEfectivo == 2 ? 'Histórico Completo' : (alcanceEfectivo == 1 ? 'Tabla Anual $anioFiltro' : torneoRef),
                              docs,
                              todosDocs,
                              hayVariosTorneos: hayVariosTorneos,
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
                          ),
                        );
                      },
                    ),
                  ],
                ],

                if (_vistaSeleccionada == 1) ...[
                  if (docs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Text(
                          _alcanceFiltro == 2
                              ? 'No hay partidos registrados.'
                              : (alcanceEfectivo == 1 ? 'No hay partidos registrados en $anioFiltro.' : 'No hay partidos en este torneo.'),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final docId = docs[index].id;
                        final fecha = data['fecha'] ?? 'Fecha';
                        final torneoDoc = (data['torneo'] ?? '').toString();
                        final eqA = data['equipoA_nombre'] ?? 'Equipo Celeste';
                        final eqB = data['equipoB_nombre'] ?? 'Equipo Amarillo';
                        final int golesA = data['equipoA_goles'] ?? 0;
                        final int golesB = data['equipoB_goles'] ?? 0;
                        final List jugsA = data['equipoA_jugadores'] ?? [];
                        final List jugsB = data['equipoB_jugadores'] ?? [];
                        final String videoUrl = (data['videoUrl'] ?? '').toString().trim();
                        final Map<String, dynamic> tantosDoc = data['tantos'] is Map
                            ? Map<String, dynamic>.from(data['tantos'] as Map)
                            : const {};

                        String formatearJugadoresConTantos(List jugs) {
                          return jugs.map((j) {
                            final raw = j.toString();
                            final nom = limpiarNombre(raw);
                            final int cant = (tantosDoc[raw] is int)
                                ? tantosDoc[raw] as int
                                : (int.tryParse('${tantosDoc[raw] ?? tantosDoc[nom] ?? 0}') ?? 0);
                            return cant > 0 ? '$nom ($cant)' : nom;
                          }).join(', ');
                        }

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
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              alcanceEfectivo != 0 && torneoDoc.isNotEmpty
                                                  ? '$fecha • $torneoDoc'
                                                  : fecha,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.lightBlueAccent,
                                              ),
                                            ),
                                          ),
                                          if (videoUrl.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            const Icon(Icons.videocam, color: Colors.tealAccent, size: 16),
                                          ],
                                        ],
                                      ),
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
                                        formatearJugadoresConTantos(jugsA),
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
                                        formatearJugadoresConTantos(jugsB),
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
                  _buildVistaEstadisticas(
                    docs,
                    alcanceEfectivo: alcanceEfectivo,
                    torneoRef: torneoRef,
                    anioFiltro: anioFiltro,
                  ),
                ],

                if (_vistaSeleccionada == 1 && widget.puedeCargarResultado)
                  const SizedBox(height: 72),
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

class _PuntoProgreso {
  final int fechaNum;
  final String fechaTexto;
  final String torneo;
  final int posicion;
  final int totalJugadores;
  final int puntos;
  final int deltaPosicion;
  final bool jugoEstaFecha;
  final String resultadoTexto;
  final String marcadorTexto;

  _PuntoProgreso({
    required this.fechaNum,
    required this.fechaTexto,
    required this.torneo,
    required this.posicion,
    required this.totalJugadores,
    required this.puntos,
    required this.deltaPosicion,
    required this.jugoEstaFecha,
    required this.resultadoTexto,
    required this.marcadorTexto,
  });
}

class _StatsAcumuladas {
  int pj = 0;
  int pts = 0;
  double get promedio => pj > 0 ? pts / pj : 0.0;
}

class _ProgresoJugadorSheet extends StatefulWidget {
  final String nombreJugador;
  final String tituloVistaActual;
  final List<QueryDocumentSnapshot<Object?>> docsVistaActual;
  final List<QueryDocumentSnapshot<Object?>> docsTodosLosTorneos;
  final List<Jugador> titulares;
  final List<Jugador> suplentes;
  final bool hayVariosTorneos;

  const _ProgresoJugadorSheet({
    required this.nombreJugador,
    required this.tituloVistaActual,
    required this.docsVistaActual,
    required this.docsTodosLosTorneos,
    required this.titulares,
    required this.suplentes,
    this.hayVariosTorneos = true,
  });

  @override
  State<_ProgresoJugadorSheet> createState() => _ProgresoJugadorSheetState();
}

class _ProgresoJugadorSheetState extends State<_ProgresoJugadorSheet> {
  bool _verHistorico = false;
  bool _verPuntos = false;

  String _canonicalizar(String raw) {
    final l = limpiarNombre(raw);
    final base = l.isNotEmpty ? l : raw.trim();
    for (final t in [...widget.titulares, ...widget.suplentes]) {
      if (sonElMismoJugador(t.nombre, base)) {
        return t.nombre;
      }
    }
    return base;
  }

  List<_PuntoProgreso> _calcularSerie(
    List<QueryDocumentSnapshot<Object?>> docsDesc,
  ) {
    final cronologicos = docsDesc.reversed.toList();
    final Map<String, _StatsAcumuladas> tablaTemp = {};
    final List<_PuntoProgreso> puntos = [];
    int? posAnterior;

    for (int i = 0; i < cronologicos.length; i++) {
      final data = cronologicos[i].data() as Map<String, dynamic>;
      final int golesA = data['equipoA_goles'] ?? 0;
      final int golesB = data['equipoB_goles'] ?? 0;
      final List rawA = data['equipoA_jugadores'] ?? [];
      final List rawB = data['equipoB_jugadores'] ?? [];
      final String torneo = (data['torneo'] ?? '').toString();
      final String fechaStr = (data['fecha'] ?? 'Fecha ${i + 1}').toString();

      bool jugo = false;
      String resTexto = '-';
      String marcador = 'No jugó esta fecha';

      for (final j in rawA) {
        final nom = _canonicalizar(j.toString());
        if (nom.isEmpty) continue;
        final st = tablaTemp.putIfAbsent(nom, () => _StatsAcumuladas());
        st.pj += 1;
        if (golesA > golesB) {
          st.pts += 3;
        } else if (golesA == golesB) {
          st.pts += 1;
        }
        if (sonElMismoJugador(nom, widget.nombreJugador)) {
          jugo = true;
          resTexto = golesA > golesB ? 'G' : (golesA == golesB ? 'E' : 'P');
          marcador = golesA > golesB
              ? 'Ganó $golesA - $golesB ($fechaStr)'
              : (golesA == golesB
                  ? 'Empató $golesA - $golesB ($fechaStr)'
                  : 'Perdió $golesA - $golesB ($fechaStr)');
        }
      }

      for (final j in rawB) {
        final nom = _canonicalizar(j.toString());
        if (nom.isEmpty) continue;
        final st = tablaTemp.putIfAbsent(nom, () => _StatsAcumuladas());
        st.pj += 1;
        if (golesB > golesA) {
          st.pts += 3;
        } else if (golesB == golesA) {
          st.pts += 1;
        }
        if (sonElMismoJugador(nom, widget.nombreJugador)) {
          jugo = true;
          resTexto = golesB > golesA ? 'G' : (golesB == golesA ? 'E' : 'P');
          marcador = golesB > golesA
              ? 'Ganó $golesB - $golesA ($fechaStr)'
              : (golesB == golesA
                  ? 'Empató $golesB - $golesA ($fechaStr)'
                  : 'Perdió $golesB - $golesA ($fechaStr)');
        }
      }

      final ranking = tablaTemp.entries.toList()
        ..sort((a, b) {
          final int cmpPts = b.value.pts.compareTo(a.value.pts);
          if (cmpPts != 0) return cmpPts;
          final int cmpProm = b.value.promedio.compareTo(a.value.promedio);
          if (cmpProm != 0) return cmpProm;
          return a.value.pj.compareTo(b.value.pj);
        });

      final idxJugador = ranking
          .indexWhere((e) => sonElMismoJugador(e.key, widget.nombreJugador));

      if (idxJugador != -1) {
        final int posActual = idxJugador + 1;
        final int ptsActual = ranking[idxJugador].value.pts;
        final int delta = posAnterior != null ? (posAnterior - posActual) : 0;
        posAnterior = posActual;

        puntos.add(_PuntoProgreso(
          fechaNum: i + 1,
          fechaTexto: fechaStr,
          torneo: torneo,
          posicion: posActual,
          totalJugadores: ranking.length,
          puntos: ptsActual,
          deltaPosicion: delta,
          jugoEstaFecha: jugo,
          resultadoTexto: resTexto,
          marcadorTexto: marcador,
        ));
      }
    }

    return puntos;
  }

  @override
  Widget build(BuildContext context) {
    final docsBase =
        _verHistorico ? widget.docsTodosLosTorneos : widget.docsVistaActual;
    final serie = _calcularSerie(docsBase);

    final int maxRank = serie.isEmpty
        ? 10
        : serie
            .map((p) => p.totalJugadores)
            .reduce((a, b) => a > b ? a : b);

    final int puestoActual = serie.isNotEmpty ? serie.last.posicion : 0;
    final int mejorPuesto = serie.isNotEmpty
        ? serie.map((p) => p.posicion).reduce((a, b) => a < b ? a : b)
        : 0;
    final int puntosFinal = serie.isNotEmpty ? serie.last.puntos : 0;
    final int variacionTotal =
        serie.length >= 2 ? (serie.first.posicion - serie.last.posicion) : 0;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.lightBlueAccent,
                  child: Icon(Icons.show_chart, color: Colors.black, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progreso de ${widget.nombreJugador}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _verHistorico
                            ? 'Todos los torneos del grupo'
                            : widget.tituloVistaActual,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (widget.hayVariosTorneos) ...[
                  Expanded(
                    flex: 11,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(11),
                              onTap: () => setState(() => _verHistorico = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 7, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: !_verHistorico
                                      ? Colors.lightBlueAccent
                                          .withValues(alpha: 0.25)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'Torneo',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: !_verHistorico
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: !_verHistorico
                                          ? Colors.lightBlueAccent
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(11),
                              onTap: () => setState(() => _verHistorico = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 7, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: _verHistorico
                                      ? Colors.amberAccent.withValues(alpha: 0.25)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'Histórico',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _verHistorico
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: _verHistorico
                                          ? Colors.amberAccent
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 10,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => setState(() => _verPuntos = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 7, horizontal: 4),
                              decoration: BoxDecoration(
                                color: !_verPuntos
                                    ? Colors.lightBlueAccent
                                        .withValues(alpha: 0.25)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Puesto #',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: !_verPuntos
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: !_verPuntos
                                        ? Colors.white
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => setState(() => _verPuntos = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 7, horizontal: 4),
                              decoration: BoxDecoration(
                                color: _verPuntos
                                    ? Colors.greenAccent.withValues(alpha: 0.25)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Puntos',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _verPuntos
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _verPuntos
                                        ? Colors.greenAccent
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (serie.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Sin partidos registrados para graficar.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildKpiCard(
                      'Actual', '#$puestoActual', Colors.lightBlueAccent),
                  const SizedBox(width: 8),
                  _buildKpiCard(
                      'Mejor', '#$mejorPuesto', Colors.amberAccent),
                  const SizedBox(width: 8),
                  _buildKpiCard('Puntos', '$puntosFinal', Colors.greenAccent),
                  const SizedBox(width: 8),
                  _buildKpiCard(
                    'Balance',
                    variacionTotal > 0
                        ? '▲ +$variacionTotal'
                        : (variacionTotal < 0 ? '▼ $variacionTotal' : '='),
                    variacionTotal > 0
                        ? Colors.greenAccent
                        : (variacionTotal < 0
                            ? Colors.redAccent
                            : Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 210,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1724),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.lightBlueAccent.withValues(alpha: 0.2)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double minWidth = constraints.maxWidth;
                  final double chartWidth =
                      (serie.length * 52.0).clamp(minWidth, 4000.0);
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: chartWidth,
                      height: 185,
                      child: CustomPaint(
                        painter: _GraficoProgresoPainter(
                          puntos: serie,
                          maxRank: maxRank,
                          modoPuntos: _verPuntos,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Detalle fecha por fecha',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: serie.length,
                itemBuilder: (context, idx) {
                  final item = serie[serie.length - 1 - idx];
                  final Color colorRes = item.resultadoTexto == 'G'
                      ? Colors.greenAccent
                      : (item.resultadoTexto == 'E'
                          ? Colors.amberAccent
                          : (item.resultadoTexto == 'P'
                              ? Colors.redAccent
                              : Colors.grey));

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: Colors.white.withValues(alpha: 0.03),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: colorRes.withValues(alpha: 0.18),
                        child: Text(
                          item.resultadoTexto,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorRes,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            'Fecha ${item.fechaNum}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (_verHistorico && item.torneo.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '(${item.torneo})',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        item.marcadorTexto,
                        style: TextStyle(
                            fontSize: 11,
                            color: item.jugoEstaFecha
                                ? Colors.white70
                                : Colors.grey),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.deltaPosicion != 0)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (item.deltaPosicion > 0
                                        ? Colors.greenAccent
                                        : Colors.redAccent)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.deltaPosicion > 0
                                    ? '▲ +${item.deltaPosicion}'
                                    : '▼ ${item.deltaPosicion}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: item.deltaPosicion > 0
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                ),
                              ),
                            ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '#${item.posicion}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.lightBlueAccent,
                                ),
                              ),
                              Text(
                                '${item.puntos} pts',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.greenAccent),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraficoProgresoPainter extends CustomPainter {
  final List<_PuntoProgreso> puntos;
  final int maxRank;
  final bool modoPuntos;

  _GraficoProgresoPainter({
    required this.puntos,
    required this.maxRank,
    required this.modoPuntos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (puntos.isEmpty) return;

    const double padLeft = 34.0;
    const double padRight = 22.0;
    const double padTop = 22.0;
    const double padBottom = 24.0;

    final double plotW = (size.width - padLeft - padRight).clamp(10.0, 99999.0);
    final double plotH = (size.height - padTop - padBottom).clamp(10.0, 99999.0);

    final int maxPts = puntos
        .map((p) => p.puntos)
        .reduce((a, b) => a > b ? a : b)
        .clamp(3, 9999);

    double yParaPunto(_PuntoProgreso p) {
      if (modoPuntos) {
        final ratio = (p.puntos / maxPts).clamp(0.0, 1.0);
        return padTop + plotH * (1.0 - ratio);
      } else {
        if (maxRank <= 1) return padTop + plotH / 2;
        final ratio = ((p.posicion - 1) / (maxRank - 1)).clamp(0.0, 1.0);
        return padTop + plotH * ratio;
      }
    }

    double xParaIndice(int i) {
      if (puntos.length == 1) return padLeft + plotW / 2;
      return padLeft + (plotW * i / (puntos.length - 1));
    }

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    final List<double> gridRatios = [0.0, 0.5, 1.0];
    for (final r in gridRatios) {
      final y = padTop + plotH * r;
      canvas.drawLine(Offset(padLeft, y), Offset(padLeft + plotW, y), gridPaint);

      final String labelY;
      if (modoPuntos) {
        final val = ((1.0 - r) * maxPts).round();
        labelY = '$val';
      } else {
        final rankVal = (1 + r * (maxRank - 1)).round();
        labelY = '#$rankVal';
      }

      final tp = TextPainter(
        text: TextSpan(
          text: labelY,
          style: const TextStyle(color: Colors.grey, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    final List<Offset> coords = [];
    for (int i = 0; i < puntos.length; i++) {
      coords.add(Offset(xParaIndice(i), yParaPunto(puntos[i])));
    }

    final Color lineColor =
        modoPuntos ? Colors.greenAccent : Colors.lightBlueAccent;

    if (coords.length >= 2) {
      final areaPath = Path()..moveTo(coords.first.dx, padTop + plotH);
      for (final c in coords) {
        areaPath.lineTo(c.dx, c.dy);
      }
      areaPath.lineTo(coords.last.dx, padTop + plotH);
      areaPath.close();

      final areaPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.28),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(padLeft, padTop, plotW, plotH));
      canvas.drawPath(areaPath, areaPaint);

      final linePath = Path()..moveTo(coords.first.dx, coords.first.dy);
      for (int i = 1; i < coords.length; i++) {
        linePath.lineTo(coords[i].dx, coords[i].dy);
      }
      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(linePath, linePaint);
    }

    for (int i = 0; i < puntos.length; i++) {
      final p = puntos[i];
      final c = coords[i];

      final Color dotColor = !p.jugoEstaFecha
          ? Colors.grey
          : (p.resultadoTexto == 'G'
              ? Colors.greenAccent
              : (p.resultadoTexto == 'E'
                  ? Colors.amberAccent
                  : Colors.redAccent));

      canvas.drawCircle(c, 5.5, Paint()..color = const Color(0xFF0E1724));
      canvas.drawCircle(c, 4.0, Paint()..color = dotColor);

      final String valTxt = modoPuntos ? '${p.puntos}' : '#${p.posicion}';
      final valPainter = TextPainter(
        text: TextSpan(
          text: valTxt,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valPainter.paint(
        canvas,
        Offset(c.dx - valPainter.width / 2, (c.dy - 16).clamp(0.0, size.height)),
      );

      final fPainter = TextPainter(
        text: TextSpan(
          text: 'F${p.fechaNum}',
          style: const TextStyle(color: Colors.grey, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      fPainter.paint(
        canvas,
        Offset(c.dx - fPainter.width / 2, padTop + plotH + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GraficoProgresoPainter oldDelegate) {
    return oldDelegate.puntos != puntos ||
        oldDelegate.modoPuntos != modoPuntos ||
        oldDelegate.maxRank != maxRank;
  }
}
