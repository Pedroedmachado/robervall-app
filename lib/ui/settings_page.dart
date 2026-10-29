import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    void q() => store.saveLater();
    void r() => store.changed();

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    title: 'Dados da oficina (saem no PDF)',
                    icon: Icons.store_outlined,
                    children: [
                      FieldGrid(children: [
                        BoundField(
                            label: 'Nome da oficina',
                            value: s.shopName,
                            capitalization: TextCapitalization.words,
                            onChanged: (t) {
                              s.shopName = t;
                              q();
                            }),
                        BoundField(
                            label: 'CNPJ / CPF',
                            value: s.shopDoc,
                            onChanged: (t) {
                              s.shopDoc = t;
                              q();
                            }),
                        BoundField(
                            label: 'Telefone / WhatsApp',
                            value: s.shopPhone,
                            keyboard: TextInputType.phone,
                            onChanged: (t) {
                              s.shopPhone = t;
                              q();
                            }),
                        BoundField(
                            label: 'E-mail',
                            value: s.shopEmail,
                            keyboard: TextInputType.emailAddress,
                            capitalization: TextCapitalization.none,
                            onChanged: (t) {
                              s.shopEmail = t;
                              q();
                            }),
                      ]),
                      const SizedBox(height: 12),
                      BoundField(
                          label: 'Endereço',
                          value: s.shopAddress,
                          onChanged: (t) {
                            s.shopAddress = t;
                            q();
                          }),
                    ],
                  ),
                  SectionCard(
                    title: 'Valor da hora',
                    icon: Icons.schedule,
                    children: [
                      FieldGrid(children: [
                        for (final lt in LaborType.values)
                          NumField(
                            label: lt.label,
                            prefix: 'R\$',
                            suffix: '/h',
                            value: s.rateFor(lt),
                            onChanged: (n) {
                              s.laborRates[lt.name] = n;
                              r();
                            },
                          ),
                        NumField(
                          label: 'Pintura (mão de obra)',
                          prefix: 'R\$',
                          suffix: '/h',
                          value: s.paintRate,
                          onChanged: (n) {
                            s.paintRate = n;
                            r();
                          },
                        ),
                        NumField(
                          label: 'Material de pintura',
                          prefix: 'R\$',
                          suffix: '/h',
                          value: s.paintMaterialRate,
                          onChanged: (n) {
                            s.paintMaterialRate = n;
                            r();
                          },
                        ),
                      ]),
                    ],
                  ),
                  SectionCard(
                    title: 'Orçamento',
                    icon: Icons.request_quote_outlined,
                    children: [
                      FieldGrid(children: [
                        BoundField(
                            label: 'Prefixo da numeração',
                            value: s.numberPrefix,
                            capitalization: TextCapitalization.characters,
                            onChanged: (t) {
                              s.numberPrefix = t.trim().isEmpty ? 'FN' : t.trim();
                              q();
                            }),
                        NumField(
                          label: 'Próximo número',
                          value: s.nextNumber.toDouble(),
                          onChanged: (n) {
                            s.nextNumber = n < 1 ? 1 : n.round();
                            q();
                          },
                        ),
                        NumField(
                          label: 'Validade do orçamento',
                          suffix: 'dias',
                          value: s.budgetValidityDays.toDouble(),
                          onChanged: (n) {
                            s.budgetValidityDays = n.round();
                            q();
                          },
                        ),
                        NumField(
                          label: 'Alerta de perda total',
                          suffix: '% da FIPE',
                          value: s.totalLossPct,
                          onChanged: (n) {
                            s.totalLossPct = n <= 0 ? 75 : n;
                            r();
                          },
                        ),
                      ]),
                      const SizedBox(height: 12),
                      BoundField(
                          label: 'Texto do rodapé do PDF',
                          value: s.budgetFooter,
                          maxLines: 3,
                          onChanged: (t) {
                            s.budgetFooter = t;
                            q();
                          }),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Cobrar mão de obra por peça'),
                        subtitle: const Text(
                            'Itens novos já abrem com um valor por peça (reparo e pintura juntos), sem horas.'),
                        value: s.perPieceDefault,
                        onChanged: (b) {
                          s.perPieceDefault = b;
                          r();
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mostrar horas no orçamento'),
                        subtitle: const Text(
                            'Colunas de horas de M.O. e pintura no PDF, para seguradoras que pedem.'),
                        value: s.showHours,
                        onChanged: (b) {
                          s.showHours = b;
                          r();
                        },
                      ),
                    ],
                  ),
                  SectionCard(
                    title: 'Aparência',
                    icon: Icons.palette_outlined,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'system',
                              label: Text('Sistema'),
                              icon: Icon(Icons.brightness_auto)),
                          ButtonSegment(
                              value: 'light',
                              label: Text('Claro'),
                              icon: Icon(Icons.light_mode)),
                          ButtonSegment(
                              value: 'dark',
                              label: Text('Escuro'),
                              icon: Icon(Icons.dark_mode)),
                        ],
                        selected: {s.themeMode},
                        onSelectionChanged: (v) {
                          s.themeMode = v.first;
                          r();
                        },
                      ),
                    ],
                  ),
                  const _BackupCard(),
                  SectionCard(
                    title: 'Sobre',
                    icon: Icons.info_outline,
                    children: [
                      const Text(
                          'Funilar 1.0 — orçamentos, vistorias e sinistros para oficinas. Funciona sem internet; os dados ficam neste aparelho (a consulta à Tabela FIPE usa a internet).'),
                      const SizedBox(height: 8),
                      SelectableText('Pasta dos dados: ${store.baseDir.path}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupCard extends StatefulWidget {
  const _BackupCard();

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  bool _busy = false;

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  Future<void> _export() async {
    final store = StoreScope.read(context);
    final origin = shareOrigin(context);
    setState(() => _busy = true);
    try {
      final bytes = await store.exportBackup();
      final now = DateTime.now();
      final name =
          'funilar-backup-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.zip';
      if (_mobile) {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/$name');
        await f.writeAsBytes(bytes, flush: true);
        await Share.shareXFiles([XFile(f.path, mimeType: 'application/zip')],
            subject: 'Backup Funilar', sharePositionOrigin: origin);
      } else {
        final loc = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'Backup', extensions: ['zip'])
          ],
        );
        if (loc == null) return;
        await File(loc.path).writeAsBytes(bytes, flush: true);
        if (mounted) toast(context, 'Backup salvo em ${loc.path}');
      }
    } catch (e) {
      if (mounted) toast(context, 'Falha ao gerar backup: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final store = StoreScope.read(context);
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
          label: 'Backup',
          extensions: ['zip'],
          mimeTypes: ['application/zip', 'application/x-zip-compressed'])
    ]);
    if (file == null || !mounted) return;
    final ok = await confirm(
      context,
      'Restaurar backup?',
      'Os dados atuais deste aparelho serão substituídos pelos do arquivo ${file.name}.',
      ok: 'Restaurar',
      danger: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await store.importBackup(await file.readAsBytes());
      if (mounted) {
        toast(context,
            'Backup restaurado: ${store.claims.length} registros, ${store.catalog.length} itens no catálogo.');
      }
    } catch (e) {
      if (mounted) toast(context, 'Não foi possível restaurar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final photos = store.claims.fold<int>(0, (p, c) => p + c.photos.length);
    return SectionCard(
      title: 'Backup e transferência',
      icon: Icons.backup_outlined,
      children: [
        Text(
            'Gere um arquivo .zip com todos os registros, cadastros, catálogo e fotos (${store.claims.length} registros, $photos fotos). Use para guardar cópia ou passar os dados do celular para o computador e vice-versa.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.upload_file),
            label: Text(_mobile ? 'Exportar e compartilhar' : 'Exportar backup'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.restore),
            label: const Text('Restaurar backup'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ]),
        const SizedBox(height: 8),
        Text('Tudo é salvo automaticamente neste aparelho enquanto você usa.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
