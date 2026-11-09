import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../modules.dart';
import '../pdf_words.dart';
import '../receipt_parser.dart';
import '../stock.dart';
import '../stock_entry.dart';
import '../theme.dart';
import 'access.dart';
import 'finance_page.dart' show scanReceiptPhoto;
import 'widgets.dart';

/// Estoque › Entrada pela nota: lê a nota de compra (foto, XML da NF-e ou
/// PDF) e soma as quantidades no estoque.
Future<void> stockEntryFromNote(BuildContext context) async {
  if (!await authorize(context, Perm.estoqueEditar,
      reason: 'Só o gestor/almoxarife mexe no estoque.')) {
    return;
  }
  if (!context.mounted) return;
  final mobile = Platform.isAndroid || Platform.isIOS;
  final ocr = gate.active(Mod.ocr);
  final how = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Entrada no estoque pela nota de compra',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        if (ocr)
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Foto da nota'),
            subtitle: Text(mobile
                ? 'Tire uma foto ou escolha da galeria'
                : 'A leitura da foto funciona no celular'),
            onTap: () => Navigator.pop(ctx, 'foto'),
          ),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('XML da NF-e'),
          subtitle: const Text('O arquivo .xml que o fornecedor manda por e-mail (o mais preciso)'),
          onTap: () => Navigator.pop(ctx, 'xml'),
        ),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('PDF da nota'),
          subtitle: const Text('DANFE, cupom ou orçamento em PDF'),
          onTap: () => Navigator.pop(ctx, 'pdf'),
        ),
      ]),
    ),
  );
  if (how == null || !context.mounted) return;

  ReceiptData? data;
  var photo = '';
  try {
    switch (how) {
      case 'foto':
        final scan = await scanReceiptPhoto(context);
        if (scan == null) return;
        photo = scan.file;
        data = scan.data;
        if (data == null && context.mounted) toast(context, scan.message);
      case 'xml':
        final f = await openFile(acceptedTypeGroups: const [
          XTypeGroup(
            label: 'XML da NF-e',
            extensions: ['xml'],
            mimeTypes: ['text/xml', 'application/xml'],
            uniformTypeIdentifiers: ['public.xml'],
          ),
        ]);
        if (f == null) return;
        data = parseNfeXml(await f.readAsString());
        if (data == null && context.mounted) {
          toast(context, 'Esse XML não é de uma NF-e.');
        }
      case 'pdf':
        final f = await openFile(acceptedTypeGroups: const [
          XTypeGroup(
            label: 'PDF da nota',
            extensions: ['pdf'],
            mimeTypes: ['application/pdf'],
            uniformTypeIdentifiers: ['com.adobe.pdf'],
          ),
        ]);
        if (f == null) return;
        final words = extractPdfWords(await f.readAsBytes());
        if (words.isEmpty) {
          if (context.mounted) {
            toast(context, 'Esse PDF não tem texto (parece escaneado). Use a foto da nota.');
          }
          return;
        }
        data = parseReceiptPdfWords(words);
    }
  } catch (e) {
    if (context.mounted) toast(context, 'Não foi possível ler a nota: $e');
    return;
  }
  if (data == null || !context.mounted) return;
  if (data.items.isEmpty) {
    toast(context, 'Não achei os itens nesta nota. Cadastre à mão em "Adicionar".');
    return;
  }
  await reviewStockEntry(context, data, photo: photo);
}

/// Tela de conferência: o que soma em item que já existe e o que vira item
/// novo. Também pode lançar a nota como gasto no Financeiro.
Future<void> reviewStockEntry(BuildContext context, ReceiptData data,
    {String photo = ''}) async {
  final store = StoreScope.read(context);
  final lines = planStockEntry(data, store.stock);
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _EntryPage(data: data, lines: lines, photo: photo),
  ));
  if (ok != true || !context.mounted) return;
  final created = applyStockEntry(lines, docLabel: data.docNumber);
  for (final s in created) {
    store.upsertStock(s);
  }
  store.changed();
  final n = lines.where((l) => l.include).length;
  toast(context,
      'Entrada feita: $n ${n == 1 ? 'item' : 'itens'} (${created.length} ${created.length == 1 ? 'novo' : 'novos'}).');
}

class _EntryPage extends StatefulWidget {
  const _EntryPage({required this.data, required this.lines, required this.photo});
  final ReceiptData data;
  final List<StockEntryLine> lines;
  final String photo;

  @override
  State<_EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<_EntryPage> {
  late bool _finance =
      gate.active(Mod.financeiro) && gate.can(Perm.financeiroEditar);

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final d = widget.data;
    final t = Theme.of(context);
    final count = widget.lines.where((l) => l.include).length;
    final sum = widget.lines
        .where((l) => l.include)
        .fold(0.0, (a, l) => a + l.qty * l.unitCost);

    void save() {
      if (_finance) {
        final e = d.toEntry()..receiptFile = widget.photo;
        store.upsertEntry(e);
      }
      Navigator.pop(context, true);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrada pela nota'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: count == 0 ? null : save,
              child: const Text('Dar entrada'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.supplier.isEmpty ? 'Fornecedor não identificado' : d.supplier,
                        style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text([
                      if (d.docNumber.isNotEmpty) d.docNumber,
                      if (d.date != null) date(d.date!),
                      if (d.total > 0) 'total ${money(d.total)}',
                    ].join(' · ')),
                    const SizedBox(height: 4),
                    Text('Confira cada item: o que já existe no estoque soma na quantidade; o resto vira item novo.',
                        style: t.textTheme.bodySmall),
                  ]),
                ),
              ),
              for (final (i, l) in widget.lines.indexed) _line(context, i, l),
              const SizedBox(height: 8),
              if (gate.active(Mod.financeiro) && gate.can(Perm.financeiroEditar))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _finance,
                  onChanged: (v) => setState(() => _finance = v),
                  title: const Text('Lançar também como gasto no Financeiro'),
                  subtitle: Text(d.total > 0 ? money(d.total) : 'valor da nota'),
                ),
              const SizedBox(height: 8),
              Text('$count ${count == 1 ? 'item' : 'itens'} · ${money(sum)}',
                  style: t.textTheme.titleSmall),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('entrada-confirmar'),
                onPressed: count == 0 ? null : save,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Dar entrada no estoque'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, int i, StockEntryLine l) {
    final t = Theme.of(context);
    final m = l.match;
    return Card(
      key: ValueKey('entrada-$i'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Checkbox(value: l.include, onChanged: (v) => setState(() => l.include = v ?? false)),
            Expanded(
              child: Text(l.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          if (l.include) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                m == null
                    ? 'Item novo no estoque${l.code.isEmpty ? '' : ' · cód. ${l.code}'}'
                    : 'Soma em "${m.name}" (tem ${m.qtyLabel})',
                style: t.textTheme.bodySmall?.copyWith(
                    color: m == null ? t.colorScheme.primary : Colors.green.shade700),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 120,
                  child: NumField(
                    label: m != null && m.hasPack ? 'Qtd (${m.packName})' : 'Qtd (${l.unit})',
                    value: l.qty,
                    onChanged: (v) => setState(() => l.qty = v),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: NumField(
                    label: 'Custo unitário',
                    prefix: 'R\$',
                    value: l.unitCost,
                    onChanged: (v) => setState(() => l.unitCost = v),
                  ),
                ),
                if (m == null)
                  SegmentedButton<StockKind>(
                    segments: const [
                      ButtonSegment(value: StockKind.peca, label: Text('Peça')),
                      ButtonSegment(value: StockKind.material, label: Text('Insumo')),
                    ],
                    selected: {l.kind},
                    onSelectionChanged: (s) => setState(() => l.kind = s.first),
                  )
                else
                  TextButton(
                    onPressed: () => setState(() => l.match = null),
                    child: const Text('Criar item novo'),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
