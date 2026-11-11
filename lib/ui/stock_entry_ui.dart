import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../docs.dart';
import '../format.dart';
import '../models.dart';
import '../modules.dart';
import '../pdf_words.dart';
import '../receipt_parser.dart';
import '../stock.dart';
import '../stock_entry.dart';
import '../theme.dart';
import 'docs_page.dart' show openDoc;
import 'finance_page.dart' show editFinanceEntry, scanReceiptPhoto;
import 'widgets.dart';

/// Nota de compra lida de uma foto, do XML da NF-e ou de um PDF.
class NoteRead {
  NoteRead(this.data, this.source, {this.file = '', this.bytes, this.ext = '', this.message = ''});

  /// O que foi lido (null = só a foto, sem leitura).
  final ReceiptData? data;
  final DocSource source;

  /// Foto já guardada na pasta de fotos (só para [DocSource.foto]).
  final String file;

  /// Conteúdo do arquivo (.xml / .pdf), guardado quando a pessoa confirma.
  final Uint8List? bytes;
  final String ext;
  final String message;
}

bool get _canStock => gate.active(Mod.estoque) && gate.can(Perm.estoqueEditar);
bool get _canFinance => gate.active(Mod.financeiro) && gate.can(Perm.financeiroEditar);

/// Pergunta de onde vem a nota (foto, XML, PDF) e lê.
Future<NoteRead?> pickAndReadNote(BuildContext context) async {
  final mobile = Platform.isAndroid || Platform.isIOS;
  final ocr = gate.active(Mod.ocr);
  final how = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Ler nota de compra',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        if (ocr)
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Foto da nota'),
            subtitle: Text(mobile
                ? 'Tire uma foto ou escolha da galeria'
                : 'Escolha a foto ou imagem da nota (JPG, PNG) salva no computador'),
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
  if (how == null || !context.mounted) return null;
  try {
    switch (how) {
      case 'foto':
        final scan = await scanReceiptPhoto(context);
        if (scan == null) return null;
        return NoteRead(scan.data, DocSource.foto, file: scan.file, message: scan.message);
      case 'xml':
        final f = await openFile(acceptedTypeGroups: const [
          XTypeGroup(
            label: 'XML da NF-e',
            extensions: ['xml'],
            mimeTypes: ['text/xml', 'application/xml'],
            uniformTypeIdentifiers: ['public.xml'],
          ),
        ]);
        if (f == null) return null;
        final bytes = await f.readAsBytes();
        final data = parseNfeXml(utf8.decode(bytes, allowMalformed: true));
        if (data == null) {
          if (context.mounted) toast(context, 'Esse XML não é de uma NF-e.');
          return null;
        }
        return NoteRead(data, DocSource.xml, bytes: bytes, ext: 'xml');
      default:
        final f = await openFile(acceptedTypeGroups: const [
          XTypeGroup(
            label: 'PDF da nota',
            extensions: ['pdf'],
            mimeTypes: ['application/pdf'],
            uniformTypeIdentifiers: ['com.adobe.pdf'],
          ),
        ]);
        if (f == null) return null;
        final bytes = await f.readAsBytes();
        final words = extractPdfWords(bytes);
        if (words.isEmpty) {
          if (context.mounted) {
            toast(context, 'Esse PDF não tem texto (parece escaneado). Use a foto da nota.');
          }
          return null;
        }
        return NoteRead(parseReceiptPdfWords(words), DocSource.pdf, bytes: bytes, ext: 'pdf');
    }
  } catch (e) {
    if (context.mounted) toast(context, 'Não foi possível ler a nota: $e');
    return null;
  }
}

/// Ler nota (Estoque e Financeiro usam o mesmo caminho): lê, confere e, ao
/// confirmar, guarda o documento e liga tudo — entrada no estoque, gasto no
/// Financeiro e fornecedor nos Cadastros.
Future<void> readPurchaseNote(BuildContext context) async {
  if (!_canStock && !_canFinance) {
    toast(context,
        gate.readOnly ? 'Somente consulta (licença).' : 'Seu usuário não lança notas.');
    return;
  }
  final store = StoreScope.read(context);
  final read = await pickAndReadNote(context);
  if (read == null || !context.mounted) return;

  Future<void> dropPhoto() async {
    if (read.file.isEmpty) return;
    final f = File('${store.photosDir.path}/${read.file}');
    if (await f.exists()) await f.delete();
  }

  final data = read.data;
  // sem itens lidos: a foto fica anexada e a pessoa preenche o gasto
  if (data == null || data.items.isEmpty) {
    if (read.source == DocSource.foto && _canFinance) {
      final entry = FinanceEntry(receiptFile: read.file);
      data?.applyTo(entry);
      final saved = await editFinanceEntry(context, entry,
          banner: read.message.isEmpty
              ? 'Não achei os itens nesta nota. Preencha o valor (a foto fica guardada).'
              : read.message);
      if (saved == null) {
        await dropPhoto();
        return;
      }
      store.upsertEntry(saved); // guarda o documento junto
      if (context.mounted) toast(context, 'Gasto lançado e nota guardada em Documentos.');
    } else {
      await dropPhoto();
      if (context.mounted) {
        toast(context, 'Não achei os itens nesta nota. Cadastre à mão.');
      }
    }
    return;
  }

  final same = store.sameNote(data);
  if (same != null) {
    final again = await confirm(
        context,
        'Esta nota já foi lançada',
        '${same.title}${same.number.isEmpty ? '' : ' · ${same.number}'} foi guardada em ${date(same.createdAt)}'
            '${same.inStock ? ' e já deu entrada no estoque' : ''}. Lançar de novo duplica o estoque e o gasto.',
        ok: 'Lançar de novo',
        danger: true);
    if (!again) {
      await dropPhoto();
      if (context.mounted) await openDoc(context, same);
      return;
    }
    if (!context.mounted) return;
  }
  final done = await reviewPurchaseNote(context, data,
      source: read.source, file: read.file, bytes: read.bytes, ext: read.ext);
  if (!done) await dropPhoto();
}

/// Tela de conferência. Devolve true quando a nota foi lançada.
/// Com [doc], dá entrada no estoque de uma nota que já está guardada.
Future<bool> reviewPurchaseNote(
  BuildContext context,
  ReceiptData data, {
  DocSource source = DocSource.foto,
  String file = '',
  Uint8List? bytes,
  String ext = '',
  StoredDoc? doc,
}) async {
  final store = StoreScope.read(context);
  final lines = planStockEntry(data, store.stock);
  final already = doc != null && doc.financeId.isNotEmpty;
  final r = await Navigator.of(context).push<(bool, bool)>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _EntryPage(
      data: data,
      lines: lines,
      canStock: _canStock,
      canFinance: _canFinance && !already,
      financeDone: already,
    ),
  ));
  if (r == null || !context.mounted) return false;
  final (toStock, toFinance) = r;
  final saved = await store.registerPurchase(
    data,
    lines: toStock ? lines : null,
    source: source,
    file: file,
    fileBytes: bytes,
    ext: ext,
    toFinance: toFinance,
    doc: doc,
  );
  if (!context.mounted) return true;
  final n = toStock ? lines.where((l) => l.include).length : 0;
  final parts = [
    'Nota guardada em Documentos',
    if (toStock) '$n ${n == 1 ? 'item entrou' : 'itens entraram'} no estoque',
    if (toFinance) 'gasto de ${money(data.total)} lançado',
  ];
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('${parts.join(' · ')}.'),
    action: SnackBarAction(
        label: 'Ver',
        onPressed: () {
          if (context.mounted) openDoc(context, saved);
        }),
  ));
  return true;
}

class _EntryPage extends StatefulWidget {
  const _EntryPage({
    required this.data,
    required this.lines,
    required this.canStock,
    required this.canFinance,
    required this.financeDone,
  });
  final ReceiptData data;
  final List<StockEntryLine> lines;
  final bool canStock;
  final bool canFinance;
  final bool financeDone;

  @override
  State<_EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<_EntryPage> {
  late bool _stock = widget.canStock;
  late bool _finance = widget.canFinance;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final t = Theme.of(context);
    final count = widget.lines.where((l) => l.include).length;
    final sum = widget.lines
        .where((l) => l.include)
        .fold(0.0, (a, l) => a + l.qty * l.unitCost);
    final ok = (_stock && count > 0) || _finance;

    void save() => Navigator.pop(context, (_stock && count > 0, _finance));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferir nota'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: ok ? save : null,
              child: const Text('Lançar'),
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
                    Text(
                        'Ao lançar, a nota fica guardada em Documentos, ligada ao estoque, ao Financeiro e ao fornecedor.',
                        style: t.textTheme.bodySmall),
                  ]),
                ),
              ),
              if (widget.canStock)
                SwitchListTile(
                  key: const Key('nota-estoque'),
                  contentPadding: EdgeInsets.zero,
                  value: _stock,
                  onChanged: (v) => setState(() => _stock = v),
                  title: const Text('Dar entrada no estoque'),
                  subtitle: Text(_stock
                      ? '$count ${count == 1 ? 'item' : 'itens'} · ${money(sum)}'
                      : 'os itens não entram no estoque'),
                ),
              if (widget.canFinance)
                SwitchListTile(
                  key: const Key('nota-financeiro'),
                  contentPadding: EdgeInsets.zero,
                  value: _finance,
                  onChanged: (v) => setState(() => _finance = v),
                  title: const Text('Lançar como gasto no Financeiro'),
                  subtitle: Text(d.total > 0 ? money(d.total) : 'valor da nota'),
                )
              else if (widget.financeDone)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('Gasto já lançado no Financeiro'),
                ),
              if (_stock) ...[
                const SizedBox(height: 4),
                Text(
                    'Confira cada item: o que já existe no estoque soma na quantidade; o resto vira item novo.',
                    style: t.textTheme.bodySmall),
                for (final (i, l) in widget.lines.indexed) _line(context, i, l),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('entrada-confirmar'),
                onPressed: ok ? save : null,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Lançar e guardar a nota'),
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
            if (m == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 0, 8),
                child: BoundField(
                  label: 'Nome no estoque (corrija se a leitura errou)',
                  value: l.name,
                  onChanged: (v) => l.name = v.trim().isEmpty ? l.name : v.trim(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                m == null
                    ? 'Item novo no estoque${l.packSize > 0 ? ' · ${l.packName} de ${qtyText(l.packSize, l.unit)}' : ''}${l.code.isEmpty ? '' : ' · cód. ${l.code}'}'
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
                    label: m != null
                        ? (m.hasPack ? 'Qtd (${m.packName})' : 'Qtd (${m.unit})')
                        : (l.packSize > 0 ? 'Qtd (${l.packName})' : 'Qtd (${l.unit})'),
                    value: l.qty,
                    onChanged: (v) => setState(() => l.qty = v),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: NumField(
                    label: l.packSize > 0 && m == null ? 'Custo por ${l.packName}' : 'Custo unitário',
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
