import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/jugador.dart';

class GestionPlantelScreen extends StatefulWidget {
  const GestionPlantelScreen({super.key});

  @override
  State<GestionPlantelScreen> createState() => _GestionPlantelScreenState();
}

class _GestionPlantelScreenState extends State<GestionPlantelScreen> {
  List<Jugador> _titulares = [];
  List<Jugador> _suplentes = [];
  List<String> _baneados = [];
  List<Map<String, dynamic>> _usuariosRegistrados = [];
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    try {
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
        if (data['baneados'] != null) {
          _baneados = (data['baneados'] as List).map((e) => e.toString()).toList();
        }
      }

      final usersSnap = await FirebaseFirestore.instance.collection('usuarios').get();
      _usuariosRegistrados = usersSnap.docs
          .map((d) => Map<String, dynamic>.from(d.data()))
          .toList();
    } catch (e) {
      debugPrint('Error al cargar datos del plantel: $e');
    }

    if (mounted) {
      setState(() => _cargando = false);
    }
  }

  Future<void> _guardarEnFirestore() async {
    setState(() => _guardando = true);
    await FirebaseFirestore.instance.collection('config').doc('plantel').set({
      'titulares': _titulares.map((j) => j.toMap()).toList(),
      'suplentes': _suplentes.map((j) => j.toMap()).toList(),
      'baneados': _baneados,
    }, SetOptions(merge: true));

    setState(() => _guardando = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Plantel guardado con éxito.'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  void _dialogoEditarTelefono(Jugador jugador) {
    final telCtrl = TextEditingController(text: jugador.telefono);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Teléfono de ${jugador.nombre}'),
        content: TextField(
          controller: telCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Número de WhatsApp',
            hintText: 'Ej: 1123456789',
            prefixIcon: Icon(Icons.phone, size: 18),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                jugador.telefono = telCtrl.text.trim();
              });
              _guardarEnFirestore();
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _dialogoNuevoJugador() {
    final nombreCtrl = TextEditingController();
    final telCtrl = TextEditingController();
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
                decoration: const InputDecoration(
                  labelText: 'Nombre o Apodo',
                  hintText: 'Ej: Nico',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: telCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono (Opcional)',
                  hintText: 'Ej: 1123456789',
                  prefixIcon: Icon(Icons.phone, size: 18),
                ),
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
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              onPressed: () {
                final nombre = nombreCtrl.text.trim();
                if (nombre.isNotEmpty) {
                  setState(() {
                    final item = Jugador(
                      nombre: nombre,
                      telefono: telCtrl.text.trim(),
                      esModerador: esMod,
                    );
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
    final todosLosUsuarios = snapshot.docs
        .map((d) => Map<String, dynamic>.from(d.data()))
        .toList();

    if (!mounted) return;

    final emailsOcupados = [..._titulares, ..._suplentes]
        .where((j) => j != jugador)
        .map((j) => j.email.toLowerCase().trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final uidsOcupados = [..._titulares, ..._suplentes]
        .where((j) => j != jugador)
        .map((j) => j.uid.trim())
        .where((u) => u.isNotEmpty)
        .toSet();

    final usuariosDisponibles = todosLosUsuarios.where((u) {
      final email = (u['email'] ?? '').toString().toLowerCase().trim();
      final uid = (u['uid'] ?? '').toString().trim();
      if (email.isNotEmpty && emailsOcupados.contains(email)) return false;
      if (uid.isNotEmpty && uidsOcupados.contains(uid)) return false;
      return true;
    }).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Asociar a "${jugador.nombre}"'),
        content: SizedBox(
          width: double.maxFinite,
          child: usuariosDisponibles.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Text(
                    'No hay cuentas registradas libres para vincular.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: usuariosDisponibles.length,
                  itemBuilder: (context, index) {
                    final u = usuariosDisponibles[index];
                    final String email = (u['email'] ?? '').toString();
                    final String nombreMostrar = nombreLegibleUsuario(u);
                    final bool esEste =
                        jugador.email.toLowerCase().trim() == email.toLowerCase().trim() &&
                            email.isNotEmpty;

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: Colors.white10,
                        child: Text(
                          nombreMostrar.isNotEmpty ? nombreMostrar[0].toUpperCase() : 'U',
                        ),
                      ),
                      title: Text(nombreMostrar),
                      subtitle: Text(
                        email,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      trailing: esEste
                          ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                          : null,
                      onTap: () {
                        setState(() {
                          jugador.email = email;
                          jugador.uid = (u['uid'] ?? '').toString();
                          if (jugador.nombre.trim().isEmpty ||
                              jugador.nombre.toLowerCase().contains('jugador')) {
                            jugador.nombre = nombreMostrar;
                          }
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

  void _dialogoVincularAUnoExistente(
    String nombreGoogle,
    String emailGoogle,
    String uidGoogle,
  ) {
    final sinVincular = [..._titulares, ..._suplentes]
        .where((j) => j.email.isEmpty)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Vincular "$nombreGoogle" con:'),
        content: SizedBox(
          width: double.maxFinite,
          child: sinVincular.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Todos los jugadores del plantel ya tienen una cuenta vinculada.',
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: sinVincular.length,
                  itemBuilder: (context, index) {
                    final j = sinVincular[index];
                    final bool esTit = _titulares.contains(j);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.person,
                        color: esTit ? Colors.greenAccent : Colors.orangeAccent,
                      ),
                      title: Text(
                        j.nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        esTit ? 'Titular' : 'Suplente',
                        style: TextStyle(
                          fontSize: 10,
                          color: esTit ? Colors.greenAccent : Colors.orangeAccent,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          j.email = emailGoogle;
                          j.uid = uidGoogle;
                        });
                        _guardarEnFirestore();
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ],
      ),
    );
  }

  void _toggleBanJugador(Jugador j) {
    setState(() {
      j.baneado = !j.baneado;
      final emailNorm = j.email.toLowerCase().trim();
      if (j.baneado) {
        if (emailNorm.isNotEmpty && !_baneados.contains(emailNorm)) _baneados.add(emailNorm);
        if (j.uid.isNotEmpty && !_baneados.contains(j.uid)) _baneados.add(j.uid);
      } else {
        _baneados.remove(emailNorm);
        _baneados.remove(j.uid);
      }
    });
    _guardarEnFirestore();
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
    final todosPlantel = [..._titulares, ..._suplentes];
    final emailsAsociados = todosPlantel
        .map((j) => j.email.toLowerCase().trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final uidsAsociados = todosPlantel
        .map((j) => j.uid.trim())
        .where((u) => u.isNotEmpty)
        .toSet();

    final noAsociados = _usuariosRegistrados.where((u) {
      final email = (u['email'] ?? '').toString().toLowerCase().trim();
      final uid = (u['uid'] ?? '').toString().trim();
      return !emailsAsociados.contains(email) &&
          (uid.isEmpty || !uidsAsociados.contains(uid));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Gestión de Plantel',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_guardando)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
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
                    label: const Text(
                      'Agregar Nuevo Jugador',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Titulares
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Titulares en Rotación (${_titulares.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                        ),
                      ),
                      const Text(
                        'Arriba = más prioridad',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_titulares.isEmpty)
                    Card(
                      color: Colors.white.withValues(alpha: 0.02),
                      child: const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: Text(
                            'No hay titulares cargados. Usá el botón para agregarlos.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
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
                          color: j.baneado ? const Color(0xFF3B1616) : const Color(0xFF16253B),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            onTap: () => _dialogoEditarTelefono(j),
                            leading: CircleAvatar(
                              radius: 12,
                              backgroundColor: j.baneado
                                  ? Colors.red.shade900
                                  : (index < 10 ? Colors.green.shade800 : Colors.orange.shade900),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    j.nombre,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      decoration: j.baneado ? TextDecoration.lineThrough : null,
                                      color: j.baneado ? Colors.redAccent : Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (j.baneado) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade900,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'BANEADO',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                                if (j.esModerador) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade800,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'MOD',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vinculado ? j.email : 'Sin vincular a Google',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: vinculado ? Colors.greenAccent : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                if (j.telefono.trim().isNotEmpty)
                                  Text(
                                    '📞 ${j.telefono}',
                                    style: const TextStyle(fontSize: 10, color: Colors.tealAccent),
                                  )
                                else
                                  const Text(
                                    '📞 Sin teléfono (tocá para agregar)',
                                    style: TextStyle(fontSize: 10, color: Colors.white38),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildBotonAccion(
                                  icon: j.baneado ? Icons.lock_open : Icons.block,
                                  color: j.baneado ? Colors.redAccent : Colors.grey.shade600,
                                  tooltip: j.baneado ? 'Desbanear' : 'Banear jugador',
                                  onPressed: () => _toggleBanJugador(j),
                                ),
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

                  // Suplentes
                  Text(
                    'Suplentes / Reservas (${_suplentes.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orangeAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_suplentes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'No hay suplentes cargados.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
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
                          color: j.baneado ? const Color(0xFF3B1616) : Colors.white.withValues(alpha: 0.03),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            onTap: () => _dialogoEditarTelefono(j),
                            leading: CircleAvatar(
                              radius: 12,
                              backgroundColor: j.baneado ? Colors.red.shade900 : Colors.white12,
                              child: Icon(j.baneado ? Icons.block : Icons.person, size: 14, color: Colors.grey),
                            ),
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    j.nombre,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      decoration: j.baneado ? TextDecoration.lineThrough : null,
                                      color: j.baneado ? Colors.redAccent : Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (j.baneado) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade900,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'BANEADO',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vinculado ? j.email : 'Sin vincular a Google',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: vinculado ? Colors.greenAccent : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                if (j.telefono.trim().isNotEmpty)
                                  Text(
                                    '📞 ${j.telefono}',
                                    style: const TextStyle(fontSize: 10, color: Colors.tealAccent),
                                  )
                                else
                                  const Text(
                                    '📞 Sin teléfono (tocá para agregar)',
                                    style: TextStyle(fontSize: 10, color: Colors.white38),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildBotonAccion(
                                  icon: j.baneado ? Icons.lock_open : Icons.block,
                                  color: j.baneado ? Colors.redAccent : Colors.grey.shade600,
                                  tooltip: j.baneado ? 'Desbanear' : 'Banear jugador',
                                  onPressed: () => _toggleBanJugador(j),
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

                  const Divider(height: 32),

                  // Cuentas Sin Vincular
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Cuentas Registradas Sin Vincular (${noAsociados.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.cyanAccent,
                        ),
                      ),
                      if (noAsociados.isNotEmpty)
                        Text(
                          '${noAsociados.length} pendientes',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (noAsociados.isEmpty)
                    Card(
                      color: Colors.white.withValues(alpha: 0.02),
                      child: const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: Text(
                            'Todas las cuentas registradas están vinculadas al plantel.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: noAsociados.length,
                      itemBuilder: (context, index) {
                        final u = noAsociados[index];
                        final String nombreMostrar = nombreLegibleUsuario(u);
                        final String emailGoogle = (u['email'] ?? '').toString();
                        final String uidGoogle = (u['uid'] ?? '').toString();
                        final String? fotoUrl = u['fotoUrl']?.toString();
                        final bool estaBaneado = _baneados.contains(emailGoogle.toLowerCase().trim()) ||
                            _baneados.contains(uidGoogle);

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: estaBaneado
                              ? const Color(0xFF3B1616)
                              : Colors.cyanAccent.withValues(alpha: 0.05),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: estaBaneado
                                  ? Colors.redAccent
                                  : Colors.cyanAccent.withValues(alpha: 0.2),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.white12,
                              backgroundImage: (fotoUrl != null && fotoUrl.isNotEmpty)
                                  ? NetworkImage(
                                      'https://images.weserv.nl/?url=${Uri.encodeComponent(fotoUrl)}',
                                    )
                                  : null,
                              child: (fotoUrl == null || fotoUrl.isEmpty)
                                  ? Text(
                                      nombreMostrar.isNotEmpty ? nombreMostrar[0].toUpperCase() : 'U',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    nombreMostrar,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: estaBaneado ? Colors.redAccent : Colors.white,
                                      decoration: estaBaneado ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                ),
                                if (estaBaneado)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade900,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'BANEADO',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              emailGoogle,
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18, color: Colors.cyanAccent),
                              tooltip: 'Opciones de cuenta',
                              onSelected: (val) {
                                if (val == 'banear') {
                                  setState(() {
                                    if (estaBaneado) {
                                      _baneados.remove(emailGoogle.toLowerCase().trim());
                                      _baneados.remove(uidGoogle);
                                    } else {
                                      if (emailGoogle.isNotEmpty) _baneados.add(emailGoogle.toLowerCase().trim());
                                      if (uidGoogle.isNotEmpty) _baneados.add(uidGoogle);
                                    }
                                  });
                                  _guardarEnFirestore();
                                } else if (val == 'titular') {
                                  setState(() {
                                    _titulares.add(Jugador(
                                      nombre: nombreMostrar,
                                      email: emailGoogle,
                                      uid: uidGoogle,
                                      baneado: estaBaneado,
                                    ));
                                  });
                                  _guardarEnFirestore();
                                } else if (val == 'suplente') {
                                  setState(() {
                                    _suplentes.add(Jugador(
                                      nombre: nombreMostrar,
                                      email: emailGoogle,
                                      uid: uidGoogle,
                                      baneado: estaBaneado,
                                    ));
                                  });
                                  _guardarEnFirestore();
                                } else if (val == 'vincular') {
                                  _dialogoVincularAUnoExistente(nombreMostrar, emailGoogle, uidGoogle);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'vincular',
                                  child: Row(
                                    children: [
                                      Icon(Icons.link, size: 18, color: Colors.lightBlueAccent),
                                      SizedBox(width: 8),
                                      Text('Vincular a jugador existente...'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'titular',
                                  child: Row(
                                    children: [
                                      Icon(Icons.add_circle_outline, size: 18, color: Colors.greenAccent),
                                      SizedBox(width: 8),
                                      Text('Agregar como Titular'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'suplente',
                                  child: Row(
                                    children: [
                                      Icon(Icons.person_add_outlined, size: 18, color: Colors.orangeAccent),
                                      SizedBox(width: 8),
                                      Text('Agregar como Suplente'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'banear',
                                  child: Row(
                                    children: [
                                      Icon(estaBaneado ? Icons.lock_open : Icons.block,
                                          size: 18, color: estaBaneado ? Colors.greenAccent : Colors.redAccent),
                                      const SizedBox(width: 8),
                                      Text(estaBaneado ? 'Desbanear usuario' : 'Banear jugador'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
