import 'package:flutter/material.dart';
import '../config/app_version.dart';
import '../services/update_service.dart';

/// Diálogo para confirmação, download e instalação de atualização.
class UpdateDialog extends StatefulWidget {
  final ReleaseInfo info;

  const UpdateDialog({super.key, required this.info});

  static Future<void> show(BuildContext context, ReleaseInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _baixando = false;
  int _baixado = 0;
  int _total = 0;
  String? _erro;

  Future<void> _iniciarDownload() async {
    final apkUrl = widget.info.apkUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      setState(() => _erro = 'Nenhum arquivo APK encontrado neste release.');
      return;
    }

    setState(() {
      _baixando = true;
      _erro = null;
      _baixado = 0;
      _total = widget.info.apkTamanho;
    });

    try {
      await UpdateService.baixarEInstalarApk(
        apkUrl,
        onProgresso: (baixado, total) {
          if (mounted) {
            setState(() {
              _baixado = baixado;
              if (total > 0) _total = total;
            });
          }
        },
      );
      if (mounted) {
        // Fecha o diálogo após disparar a instalação
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _baixando = false;
          _erro = 'Falha no download/instalação:\n$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progresso = (_total > 0) ? (_baixado / _total).clamp(0.0, 1.0) : null;
    final baixadoMb = (_baixado / (1024 * 1024)).toStringAsFixed(1);
    final totalMb = (_total > 0) ? (_total / (1024 * 1024)).toStringAsFixed(1) : '?';
    final percentual = progresso != null ? (progresso * 100).toStringAsFixed(0) : '';

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.system_update, color: Color(0xFF13315C)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Atualização ${widget.info.tagName}',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versão instalada: ${AppVersion.display}  →  Nova: ${widget.info.tagName}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (widget.info.notas.isNotEmpty) ...[
              const Text('O que há de novo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.info.notas,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_baixando) ...[
              const Text('Baixando atualização...', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progresso),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$baixadoMb MB de $totalMb MB', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  if (percentual.isNotEmpty)
                    Text('$percentual%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
            if (_erro != null) ...[
              const SizedBox(height: 8),
              Text(
                _erro!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_baixando)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Depois'),
          ),
        if (!_baixando)
          FilledButton.icon(
            onPressed: _iniciarDownload,
            icon: const Icon(Icons.download),
            label: const Text('Atualizar Agora'),
          ),
      ],
    );
  }
}
