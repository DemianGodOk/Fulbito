import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/jugador.dart';

class RotacionScreen extends StatelessWidget {
  final bool esAdmin;
  final List<Jugador> titulares;
  final List<Jugador> suplentes;
  final String infoPartidoDia;
  final Map<String, dynamic> asistencia;
  final VoidCallback onAbrirGestionPlantel;

  const RotacionScreen({
    super.key,
    required this.esAdmin,
    required this.titulares,
    required this.suplentes,
    required this.infoPartidoDia,
    required this.asistencia,
    required this.onAbrirGestionPlantel,
  });

  String _formatearFechaCorta(String raw) {
    if (raw.isEmpty) return '';
    final dt = parsearFechaEspanol(raw);
    if (dt != null) {
      return '${dt.day}/${dt.month}';
    }
    final match = RegExp(r'(\d+/\d+)').firstMatch(raw);
    if (match != null) return match.group(1)!;
    return raw;
  }

  void _abrirSelectorCamisetas(
      BuildContext context,
      List<String> listaAlfabeticas,
      String actual,
      ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quién tiene las camisetas actualmente?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: listaAlfabeticas.length,
            itemBuilder: (context, index) {
              final nombre = listaAlfabeticas[index];
              final esEl = sonElMismoJugador(nombre, actual);
              return ListTile(
                dense: true,
                title: Text(
                  nombre,
                  style: TextStyle(
                    fontWeight: esEl ? FontWeight.bold : FontWeight.normal,
                    color: esEl ? Colors.lightBlueAccent : Colors.white,
                  ),
                ),
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

  void _abrirSelectorLeToca(
      BuildContext context,
      List<String> listaAlfabeticas,
      String manualActual,
      ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿A quién le toca llevarlas?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.autorenew, color: Colors.tealAccent),
                title: const Text(
                  'Automático (por rotación y asistencia)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent),
                ),
                subtitle: const Text(
                  'Calcula según orden alfabético y confirmaciones del partido',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
                trailing: manualActual.isEmpty
                    ? const Icon(Icons.check, color: Colors.tealAccent)
                    : null,
                onTap: () async {
                  await FirebaseFirestore.instance
                      .collection('config')
                      .doc('camisetas')
                      .update({'leTocaManual': FieldValue.delete()});
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              const Divider(),
              ...listaAlfabeticas.map((nombre) {
                final esSeleccionado = sonElMismoJugador(nombre, manualActual);
                return ListTile(
                  dense: true,
                  title: Text(
                    nombre,
                    style: TextStyle(
                      fontWeight: esSeleccionado ? FontWeight.bold : FontWeight.normal,
                      color: esSeleccionado ? Colors.orangeAccent : Colors.white,
                    ),
                  ),
                  trailing: esSeleccionado
                      ? const Icon(Icons.check, color: Colors.orangeAccent)
                      : null,
                  onTap: () async {
                    await FirebaseFirestore.instance
                        .collection('config')
                        .doc('camisetas')
                        .set({'leTocaManual': nombre}, SetOptions(merge: true));
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _dialogoEditarLavados(
      BuildContext context,
      String jugador,
      int countActual,
      Map<String, dynamic> conteoMap,
      ) {
    int valor = countActual;
    final ctrl = TextEditingController(text: '$valor');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Text('Lavados de $jugador'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Modificá la cantidad de veces que lavó las camisetas este jugador:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.remove),
                    onPressed: () {
                      if (valor > 0) {
                        setDlgState(() {
                          valor--;
                          ctrl.text = '$valor';
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: ctrl,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed >= 0) {
                          valor = parsed;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      setDlgState(() {
                        valor++;
                        ctrl.text = '$valor';
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              onPressed: () async {
                final nuevoConteo = Map<String, dynamic>.from(conteoMap);
                nuevoConteo[jugador] = valor;
                await FirebaseFirestore.instance
                    .collection('config')
                    .doc('camisetas')
                    .set({'conteo': nuevoConteo}, SetOptions(merge: true));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirEditorCola(BuildContext context) {
    List<Jugador> tempOrden = List.from(titulares);

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
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Reordenar Lista de Rotación',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Mantené presionado y arrastrá para cambiar el orden de prioridad.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
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
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            tempOrden[i].nombre,
                            style: TextStyle(
                              color: i < 10 ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ),
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
    final String fechaCorta = _formatearFechaCorta(infoPartidoDia);

    return StreamBuilder<DocumentSnapshot>(
      stream: docRefConfig.snapshots(),
      builder: (context, snapshotConfig) {
        Map<String, dynamic> dataConfig = {};
        if (snapshotConfig.hasData && snapshotConfig.data!.exists) {
          dataConfig = snapshotConfig.data!.data() as Map<String, dynamic>;
        }

        final Map<String, dynamic> conteoMap = (dataConfig['conteo'] as Map<String, dynamic>?) ?? {};
        final String deudorCamisetas = (dataConfig['deudorCamisetas'] ?? '').toString().trim();
        final String leTocaManual = (dataConfig['leTocaManual'] ?? '').toString().trim();

        final nombresTitulares = titulares.map((t) => t.nombre).toList();

        List<String> listaCamisetasAlfabeticas = List.from(nombresTitulares)
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        String lasTieneGuardado = dataConfig['lasTiene'] ??
            (listaCamisetasAlfabeticas.isNotEmpty ? listaCamisetasAlfabeticas.first : 'Sin asignar');

        int indexActual =
        listaCamisetasAlfabeticas.indexWhere((j) => sonElMismoJugador(j, lasTieneGuardado));
        String nombreVisibleLasTiene = lasTieneGuardado;

        // LÓGICA INTELIGENTE DE CAMISETAS
        String leTocaLlevarlas = 'Sin asignar';
        String motivoTurno = '';

        if (listaCamisetasAlfabeticas.isNotEmpty) {
          if (indexActual == -1) indexActual = 0;
          nombreVisibleLasTiene = listaCamisetasAlfabeticas[indexActual];

          // Si el admin asignó manualmente a alguien:
          if (leTocaManual.isNotEmpty) {
            leTocaLlevarlas = leTocaManual;
            motivoTurno = '(Asignado manualmente por el admin)';
          } else {
            // 1. Si hay un deudor que debe su turno y juega este partido, le toca a él
            final String estadoDeudor = asistencia[deudorCamisetas]?.toString() ?? '';
            if (deudorCamisetas.isNotEmpty && estadoDeudor == 'confirmado') {
              leTocaLlevarlas = deudorCamisetas;
              motivoTurno = '(Debe su turno de una fecha anterior)';
            } else {
              // 2. Si no, buscar el siguiente en el orden natural
              final String siguienteNatural =
              listaCamisetasAlfabeticas[(indexActual + 1) % listaCamisetasAlfabeticas.length];
              final String estadoSiguiente = asistencia[siguienteNatural]?.toString() ?? '';

              if (estadoSiguiente == 'baja') {
                for (int step = 2; step <= listaCamisetasAlfabeticas.length; step++) {
                  final cand =
                  listaCamisetasAlfabeticas[(indexActual + step) % listaCamisetasAlfabeticas.length];
                  final est = asistencia[cand]?.toString() ?? '';
                  if (est != 'baja') {
                    leTocaLlevarlas = cand;
                    motivoTurno = '($siguienteNatural se dio de baja, pasa al siguiente)';
                    break;
                  }
                }
                if (leTocaLlevarlas == 'Sin asignar') {
                  leTocaLlevarlas = siguienteNatural;
                }
              } else {
                leTocaLlevarlas = siguienteNatural;
              }
            }
          }
        }

        final int vecesLasTiene = (conteoMap[nombreVisibleLasTiene] ?? 0) as int;
        final int vecesLeToca = (conteoMap[leTocaLlevarlas] ?? 0) as int;

        final verdes = nombresTitulares.take(10).toList();
        final rojos = nombresTitulares.skip(10).toList();

        Widget buildChipLavados(String jugador, int veces) {
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: esAdmin ? () => _dialogoEditarLavados(context, jugador, veces, conteoMap) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: esAdmin ? Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '👕 $veces ${veces == 1 ? 'vez' : 'veces'}',
                    style: const TextStyle(fontSize: 11, color: Colors.tealAccent, fontWeight: FontWeight.w600),
                  ),
                  if (esAdmin) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 10, color: Colors.tealAccent),
                  ],
                ],
              ),
            ),
          );
        }

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
                        children: [
                          const Icon(Icons.dry_cleaning, color: Colors.lightBlueAccent, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              fechaCorta.isNotEmpty
                                  ? 'Rotación de Camisetas para el $fechaCorta'
                                  : 'Rotación de Camisetas',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),

                      // Card: Las tiene
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white12,
                              child: Icon(Icons.checkroom, color: Colors.white70, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Las tiene:',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          nombreVisibleLasTiene,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      buildChipLavados(nombreVisibleLasTiene, vecesLasTiene),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (esAdmin) ...[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Cambiar quién las tiene actualmente',
                                icon: const Icon(Icons.edit, size: 18, color: Colors.lightBlueAccent),
                                onPressed: () => _abrirSelectorCamisetas(
                                  context,
                                  listaCamisetasAlfabeticas,
                                  nombreVisibleLasTiene,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Card: Le toca llevarlas
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
                              child: Icon(Icons.arrow_forward, color: Colors.black, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Le toca llevarlas:',
                                    style: TextStyle(fontSize: 11, color: Colors.lightBlueAccent),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          leTocaLlevarlas,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.lightBlueAccent,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      buildChipLavados(leTocaLlevarlas, vecesLeToca),
                                    ],
                                  ),
                                  if (motivoTurno.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        motivoTurno,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.orangeAccent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (esAdmin) ...[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Cambiar a quién le toca',
                                icon: const Icon(Icons.edit, size: 18, color: Colors.lightBlueAccent),
                                onPressed: () => _abrirSelectorLeToca(
                                  context,
                                  listaCamisetasAlfabeticas,
                                  leTocaManual,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (deudorCamisetas.isNotEmpty && deudorCamisetas != leTocaLlevarlas)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 14, color: Colors.orangeAccent),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Pendiente: $deudorCamisetas debe su turno (se le asignará en cuanto confirme asistencia).',
                                  style: const TextStyle(fontSize: 10, color: Colors.orangeAccent),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Lista de Rotación',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
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
                          label: const Text(
                            'Plantel',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: onAbrirGestionPlantel,
                        ),
                        const SizedBox(width: 6),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          icon: const Icon(Icons.swap_vert, size: 15, color: Colors.lightBlueAccent),
                          label: const Text(
                            'Reordenar',
                            style: TextStyle(
                              color: Colors.lightBlueAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield, color: Colors.greenAccent, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'LUGAR ASEGURADO / PRIORIDAD (1 - 10)',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
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
                      child: Text(
                        'No hay titulares en rotación. Andá a "Plantel" para cargarlos.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: verdes.length,
                  itemBuilder: (context, index) {
                    final jugador = verdes[index];
                    final int vecesLavadas = (conteoMap[jugador] ?? 0) as int;

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
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          jugador,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            buildChipLavados(jugador, vecesLavadas),
                            const SizedBox(width: 8),
                            const Text(
                              'Titular',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'EN RIESGO / COLA DE ESPERA (11 - 15)',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (rojos.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'No hay jugadores en riesgo de rotación.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rojos.length,
                  itemBuilder: (context, index) {
                    final jugador = rojos[index];
                    final pos = index + 11;
                    final int vecesLavadas = (conteoMap[jugador] ?? 0) as int;

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
                          child: Text(
                            '$pos',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          jugador,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            buildChipLavados(jugador, vecesLavadas),
                            const SizedBox(width: 8),
                            Text(
                              '${index + 1}° en entrar si hay baja',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.swap_vert, color: Colors.orangeAccent, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'SUPLENTES / RESERVAS',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${suplentes.length}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
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
                    final int vecesLavadas = (conteoMap[j.nombre] ?? 0) as int;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: Colors.white.withValues(alpha: 0.02),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline, size: 18, color: Colors.grey),
                        title: Text(
                          j.nombre,
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            buildChipLavados(j.nombre, vecesLavadas),
                            const SizedBox(width: 8),
                            const Text(
                              'Reserva',
                              style: TextStyle(color: Colors.grey, fontSize: 11),
                            ),
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