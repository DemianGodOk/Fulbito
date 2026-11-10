import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import '../constants.dart';
import '../models/jugador.dart';

Future<void> verificarActualizacionGitHub(BuildContext context) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  if (kGitHubUser == 'TU_USUARIO_GITHUB') return;

  try {
    final response = await http.get(
      Uri.parse(
          'https://api.github.com/repos/$kGitHubUser/$kGitHubRepo/releases/latest'),
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'FulbitoApp',
      },
    );

    if (response.statusCode != 200) return;

    final data = jsonDecode(response.body);
    final String versionRemota =
        (data['tag_name'] ?? '').toString().replaceAll(RegExp(r'^[vV]'), '').trim();

    if (esVersionMayor(versionRemota, gAppVersion) && context.mounted) {
      String urlDescarga = '';
      final List<dynamic> assets = data['assets'] ?? [];
      for (final asset in assets) {
        final String nombreArchivo =
            (asset['name'] ?? '').toString().toLowerCase();
        if (nombreArchivo.endsWith('.apk')) {
          urlDescarga = (asset['browser_download_url'] ?? '').toString();
          break;
        }
      }

      if (urlDescarga.isNotEmpty) {
        _mostrarDialogoDescargaEInstalacion(
          context,
          versionRemota,
          gAppVersion,
          urlDescarga,
        );
      }
    }
  } catch (e) {
    debugPrint('Error al verificar actualización en GitHub: $e');
  }
}

void _mostrarDialogoDescargaEInstalacion(
  BuildContext context,
  String versionRemota,
  String versionActual,
  String urlDescarga,
) {
  bool descargando = false;
  double progreso = 0.0;
  String estadoTexto = '';
  String? errorTexto;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        void iniciarDescarga() {
          setDialogState(() {
            descargando = true;
            progreso = 0.0;
            estadoTexto = 'Iniciando descarga...';
            errorTexto = null;
          });

          try {
            OtaUpdate()
                .execute(urlDescarga, destinationFilename: 'svfc.apk')
                .listen(
              (OtaEvent event) {
                setDialogState(() {
                  switch (event.status) {
                    case OtaStatus.DOWNLOADING:
                      final valor = double.tryParse(event.value ?? '0') ?? 0.0;
                      progreso = (valor / 100.0).clamp(0.0, 1.0);
                      estadoTexto = 'Descargando: ${event.value}%';
                      break;
                    case OtaStatus.INSTALLING:
                      progreso = 1.0;
                      estadoTexto = 'Descarga completa. Abriendo instalador...';
                      break;
                    case OtaStatus.ALREADY_RUNNING_ERROR:
                      errorTexto = 'Ya hay una descarga en proceso.';
                      descargando = false;
                      break;
                    case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                      errorTexto =
                          'Permiso denegado. Habilitá "Instalar aplicaciones desconocidas" en los ajustes de Fulbito.';
                      descargando = false;
                      break;
                    default:
                      errorTexto =
                          'No se pudo completar la descarga (${event.status}).';
                      descargando = false;
                      break;
                  }
                });
              },
              onError: (e) {
                setDialogState(() {
                  errorTexto = 'Error al descargar: $e';
                  descargando = false;
                });
              },
            );
          } catch (e) {
            setDialogState(() {
              errorTexto = 'Fallo al iniciar el instalador: $e';
              descargando = false;
            });
          }
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.system_update, color: Colors.tealAccent),
              SizedBox(width: 8),
              Text('Actualización disponible', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!descargando) ...[
                Text(
                  'Hay una nueva versión ($versionRemota) de Fulbito.\nTu versión instalada: $versionActual.\n\n¿Deseás descargar e instalar la actualización ahora?',
                  style: const TextStyle(height: 1.4),
                ),
                if (errorTexto != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: Text(
                      errorTexto!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ] else ...[
                Text(
                  'Descargando versión $versionRemota...',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progreso > 0 ? progreso : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.tealAccent,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  estadoTexto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.tealAccent,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Al finalizar, el sistema abrirá la ventana para confirmar la actualización.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ],
          ),
          actions: [
            if (!descargando) ...[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Más tarde', style: TextStyle(color: Colors.grey)),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.download, size: 18),
                onPressed: iniciarDescarga,
                label: const Text('Actualizar ahora'),
              ),
            ],
          ],
        );
      },
    ),
  );
}
