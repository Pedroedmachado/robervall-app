import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../updater.dart';
import 'widgets.dart';

/// Cartão "Atualizações" (Ajustes) e a mesma tela aberta pelo aviso.
class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key, this.autoCheck = false});
  final bool autoCheck;

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  ReleaseInfo? _latest;
  String? _error;
  bool _checking = false;
  double? _progress; // baixando

  @override
  void initState() {
    super.initState();
    if (widget.autoCheck) _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final r = await fetchLatestRelease();
      if (mounted) setState(() => _latest = r);
    } catch (e) {
      if (mounted) setState(() => _error = 'Não consegui verificar (sem internet?).');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _update(ReleaseInfo rel) async {
    if (Platform.isWindows) {
      final ok = await confirm(context, 'Atualizar para ${rel.tag}?',
          'O Funilar vai baixar a versão nova, fechar e abrir de novo sozinho. Seus dados ficam como estão.',
          ok: 'Atualizar');
      if (!ok || !mounted) return;
      setState(() => _progress = 0);
      try {
        final script = await prepareWindowsUpdate(rel,
            onProgress: (p) => mounted ? setState(() => _progress = p) : null);
        if (!mounted) return;
        final store = StoreScope.read(context);
        await store.flush();
        await launchSwapScript(script);
        exit(0);
      } catch (e) {
        if (mounted) {
          setState(() => _progress = null);
          toast(context, 'Não foi possível atualizar: $e');
        }
      }
      return;
    }
    // Android (APK) e Linux: baixa o arquivo novo; iPhone: página da versão
    final name = assetForPlatform();
    final a = name == null ? null : rel.asset(name);
    final url = a?.$1 ?? releasesPage;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (mounted && Platform.isAndroid) {
      toast(context, 'Abra o arquivo baixado para instalar por cima (seus dados ficam).');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rel = _latest;
    final newer = rel != null && isNewer(rel.tag, appVersion);
    return SectionCard(
      title: 'Atualizações',
      icon: Icons.system_update_alt,
      children: [
        KeyValue('Versão instalada', appVersion == 'dev' ? 'desenvolvimento' : appVersion),
        if (rel != null)
          KeyValue('Versão mais nova', rel.tag, bold: newer),
        const SizedBox(height: 8),
        if (_error != null)
          Text(_error!, style: TextStyle(color: t.colorScheme.error)),
        if (rel != null && !newer)
          Row(children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
            const SizedBox(width: 6),
            const Expanded(child: Text('Você está na versão mais nova.')),
          ]),
        if (newer && rel.notes.trim().isNotEmpty) ...[
          Text('O que mudou:', style: t.textTheme.labelLarge),
          Text(
            rel.notes.trim().split('\n').take(8).join('\n'),
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        if (_progress != null) ...[
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 4),
          Text('Baixando… ${(_progress! * 100).round()}%', style: t.textTheme.bodySmall),
          const SizedBox(height: 8),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (newer)
            FilledButton.icon(
              onPressed: _progress != null ? null : () => _update(rel),
              icon: const Icon(Icons.download),
              label: Text(Platform.isWindows
                  ? 'Atualizar agora'
                  : (Platform.isAndroid ? 'Baixar APK novo' : 'Baixar versão nova')),
            ),
          OutlinedButton.icon(
            onPressed: _checking || _progress != null ? null : _check,
            icon: _checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: const Text('Verificar atualização'),
          ),
        ]),
      ],
    );
  }
}

/// Tela aberta pelo aviso "nova versão" que aparece ao abrir o app.
class UpdatePage extends StatelessWidget {
  const UpdatePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Atualização')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [UpdateCard(autoCheck: true)],
        ),
      );
}
