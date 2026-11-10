import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/jugador.dart';

class VestuarioScreen extends StatefulWidget {
  final String aliasUsuario;

  const VestuarioScreen({super.key, required this.aliasUsuario});

  @override
  State<VestuarioScreen> createState() => _VestuarioScreenState();
}

class _VestuarioScreenState extends State<VestuarioScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _enviando = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _enviarMensaje() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty || _enviando) return;

    setState(() => _enviando = true);
    _ctrl.clear();

    try {
      final ahora = DateTime.now().millisecondsSinceEpoch;
      final limite24hs =
          DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;

      final docRef = FirebaseFirestore.instance.collection('partidos').doc('actual_chat');
      final doc = await docRef.get();
      final List<dynamic> actuales = doc.exists
          ? (doc.data()?['mensajes'] as List<dynamic>? ?? [])
          : [];

      List<dynamic> filtrados = [];
      for (final m in actuales) {
        if (m is Map) {
          final ts = m['ts'];
          if (ts is int && ts > limite24hs) {
            filtrados.add(m);
          }
        }
      }

      filtrados.add({
        'autor': widget.aliasUsuario,
        'texto': txt,
        'ts': ahora,
      });

      if (filtrados.length > 40) {
        filtrados = filtrados.sublist(filtrados.length - 40);
      }

      await docRef.set({
        'mensajes': filtrados,
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('partidos').doc('actual').set({
        'alertaVestuario': {
          'nombre': widget.aliasUsuario,
          'texto': txt,
          'timestamp': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      _scrollHaciaAbajo();
    } catch (e) {
      debugPrint('Error al enviar mensaje en vestuario: $e');
    } finally {
      if (mounted) {
        setState(() => _enviando = false);
      }
    }
  }

  void _scrollHaciaAbajo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF16253B),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.forum_outlined, color: Colors.tealAccent, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vestuario',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Los mensajes se borran solos a las 24 horas (máx. 40).',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('partidos')
                .doc('actual_chat')
                .snapshots(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snap.data?.data() as Map<String, dynamic>? ?? {};
              final limite24hs =
                  DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
              final List<dynamic> rawMensajes = data['mensajes'] as List<dynamic>? ?? [];

              final List<dynamic> mensajes = [];
              for (final m in rawMensajes) {
                if (m is Map) {
                  final ts = m['ts'];
                  if (ts is int && ts > limite24hs) {
                    mensajes.add(m);
                  }
                }
              }

              if (mensajes.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mark_chat_unread_outlined,
                            size: 48, color: Colors.grey.shade600),
                        const SizedBox(height: 12),
                        const Text(
                          'El vestuario está tranquilo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'No hay mensajes en las últimas 24 horas.\n¡Escribí el primero para encender la charla!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });

              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                itemCount: mensajes.length,
                itemBuilder: (c, i) {
                  final m = mensajes[i];
                  final autor = m['autor']?.toString() ?? 'Jugador';
                  final texto = m['texto']?.toString() ?? '';
                  final ts = m['ts'] as int?;
                  final esMio = sonElMismoJugador(autor, widget.aliasUsuario);

                  String horaFormateada = '';
                  if (ts != null) {
                    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
                    horaFormateada =
                        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                  }

                  return Align(
                    alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      decoration: BoxDecoration(
                        color: esMio ? const Color(0xFF0F5132) : const Color(0xFF16253B),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(14),
                          topRight: const Radius.circular(14),
                          bottomLeft: Radius.circular(esMio ? 14 : 2),
                          bottomRight: Radius.circular(esMio ? 2 : 14),
                        ),
                        border: Border.all(
                          color: esMio
                              ? Colors.tealAccent.withValues(alpha: 0.3)
                              : Colors.white10,
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
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.tealAccent,
                                ),
                              ),
                            ),
                          Text(
                            texto,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              height: 1.3,
                            ),
                          ),
                          if (horaFormateada.isNotEmpty)
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  horaFormateada,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: esMio
                                        ? Colors.tealAccent.withValues(alpha: 0.7)
                                        : Colors.grey,
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
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF101C2B),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _enviarMensaje(),
                    decoration: InputDecoration(
                      hintText: 'Mensaje al vestuario...',
                      hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                  ),
                  icon: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.send, size: 18),
                  onPressed: _enviando ? null : _enviarMensaje,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
