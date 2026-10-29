import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../licensing.dart';
import '../modules.dart';
import '../store.dart';
import '../theme.dart';
import 'widgets.dart';

String _d(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Colar o texto da licença ou abrir o arquivo .lic.
Future<void> showInstallLicense(BuildContext context) async {
  final store = StoreScope.read(context);
  final ctl = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Instalar licença'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Código deste aparelho: ${store.deviceId}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
              'Cole abaixo o texto da licença (começa com FUNILAR-LICENCA-1) ou abra o arquivo .lic.'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('licenca-texto'),
            controller: ctl,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Licença'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final f = await openFile(acceptedTypeGroups: const [
                  XTypeGroup(label: 'Licença', extensions: ['lic', 'txt']),
                ]);
                if (f != null) ctl.text = await f.readAsString();
              },
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Abrir arquivo .lic'),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Instalar')),
      ],
    ),
  );
  if (text == null || text.trim().isEmpty) return;
  final r = await store.installLicense(text);
  if (!context.mounted) return;
  toast(
      context,
      r.ok
          ? 'Licença instalada: ${r.license!.customer}.'
          : 'Licença recusada: ${r.status.label}.');
}

/// Situação da licença (em Ajustes).
class LicenseCard extends StatelessWidget {
  const LicenseCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final l = store.license;
    final lic = l.license;
    final t = Theme.of(context);
    return SectionCard(
      title: 'Licença',
      icon: Icons.verified_outlined,
      children: [
        Row(children: [
          Icon(l.ok ? Icons.check_circle : Icons.error_outline,
              color: l.ok ? Colors.green.shade700 : Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
              child: Text(l.status.label,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        if (lic != null) ...[
          const SizedBox(height: 8),
          KeyValue('Cliente', lic.customer),
          if (lic.document.isNotEmpty) KeyValue('CNPJ/CPF', lic.document),
          KeyValue('Validade', lic.expires == null ? 'Sem vencimento' : _d(lic.expires!)),
          KeyValue('Aparelho', lic.device.isEmpty ? 'Qualquer' : lic.device),
          const SizedBox(height: 4),
          Text('Módulos: ${[for (final m in Mod.values) if (gate.active(m)) m.label].join(', ')}',
              style: t.textTheme.bodySmall),
        ],
        if (!l.ok) ...[
          const SizedBox(height: 4),
          Text('Sem licença válida o app abre só para consulta: nada é apagado e nada é gravado.',
              style: t.textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: SelectableText('Código deste aparelho: ${store.deviceId}',
                  style: t.textTheme.bodySmall)),
          IconButton(
            tooltip: 'Copiar código',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: store.deviceId));
              toast(context, 'Código copiado.');
            },
          ),
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: () => showInstallLicense(context),
            icon: const Icon(Icons.key),
            label: const Text('Instalar licença'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const MasterPage())),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Acesso Master'),
          ),
        ]),
      ],
    );
  }
}

/// Painel Master (fornecedor): só abre com a resposta assinada ao desafio.
class MasterPage extends StatefulWidget {
  const MasterPage({super.key});

  @override
  State<MasterPage> createState() => _MasterPageState();
}

class _MasterPageState extends State<MasterPage> {
  late String _challenge;
  final _response = TextEditingController();
  MasterSession? _session;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _challenge = newMasterChallenge(StoreScope.read(context).deviceId);
  }

  Future<void> _unlock() async {
    final store = StoreScope.read(context);
    setState(() => _busy = true);
    final s = await store.openMaster(_challenge, _response.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (s.valid) {
        _session = s;
      } else {
        // desafio de uso único: errou, gera outro
        _challenge = newMasterChallenge(store.deviceId);
        _response.clear();
      }
    });
    if (!s.valid) toast(context, 'Resposta inválida. Um novo código foi gerado.');
  }

  Future<void> _toggle(AppStore store, Mod m, bool on) async {
    final impact = store.impactOf(m, on);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${on ? 'Ligar' : 'Desligar'} ${m.label}?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (impact.blocks.isNotEmpty) ...[
              const Text('Não é possível:',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red)),
              for (final b in impact.blocks) Text('• $b'),
              const SizedBox(height: 8),
            ],
            if (impact.notes.isNotEmpty) ...[
              const Text('O que acontece:', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final n in impact.notes) Text('• $n'),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          if (impact.blocks.isEmpty)
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(on ? 'Ligar' : 'Desligar')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    try {
      await store.setModuleEnabled(m, on, _session!);
      if (mounted) toast(context, '${m.label} ${on ? 'ligado' : 'desligado'}.');
    } on AccessDenied catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Administração de módulos (Master)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _session == null
            ? [
                SectionCard(
                  title: 'Acesso restrito ao fornecedor',
                  icon: Icons.lock_outline,
                  children: [
                    const Text(
                        'Envie este código ao fornecedor do Funilar. Ele devolve uma resposta assinada que só vale para este aparelho e este pedido.'),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: SelectableText(_challenge,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ),
                      IconButton(
                        tooltip: 'Copiar código',
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _challenge));
                          toast(context, 'Código copiado.');
                        },
                      ),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('master-resposta'),
                      controller: _response,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Resposta do fornecedor'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _unlock,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Entrar'),
                    ),
                  ],
                ),
              ]
            : [
                const LicenseCard(),
                SectionCard(
                  title: 'Módulos',
                  icon: Icons.extension_outlined,
                  children: [
                    for (final m in Mod.values)
                      SwitchListTile(
                        key: ValueKey('mod-${m.name}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(m.label),
                        subtitle: Text([
                          m == Mod.nucleo
                              ? 'Sempre ativo'
                              : !gate.licensed.contains(m)
                                  ? 'Não autorizado na licença'
                                  : (gate.active(m) ? 'Autorizado · ativo' : 'Autorizado · inativo'),
                          m.description,
                          if (m.requires.isNotEmpty)
                            'Precisa de: ${m.requires.map((e) => e.label).join(', ')}',
                        ].join('\n')),
                        value: gate.active(m),
                        onChanged: m == Mod.nucleo || !gate.licensed.contains(m)
                            ? null
                            : (on) => _toggle(store, m, on),
                      ),
                  ],
                ),
                SectionCard(
                  title: 'Histórico',
                  icon: Icons.history,
                  children: [
                    if (store.activation.log.isEmpty)
                      const Text('Nenhuma alteração ainda.')
                    else
                      for (final e in store.activation.log.reversed.take(30))
                        Text(
                            '${(e['quando'] ?? '').toString().replaceFirst('T', ' ').split('.').first} · ${e['acao']}${e['modulo'] == null ? '' : ' ${Mod.byName('${e['modulo']}')?.label ?? e['modulo']}'} · ${e['obs'] ?? ''}',
                            style: t.textTheme.bodySmall),
                  ],
                ),
              ],
      ),
    );
  }
}
