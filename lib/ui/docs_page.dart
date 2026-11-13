import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../docs.dart';
import '../format.dart';
import '../models.dart';
import '../modules.dart';
import '../stock.dart';
import '../theme.dart';
import 'claims_page.dart' show openClaim;
import 'finance_page.dart' show editFinanceEntry;
import 'stock_entry_ui.dart' show reviewPurchaseNote, readPurchaseNote;
import 'widgets.dart';

/// Abre o arquivo de documentos (notas de compra e orçamentos de seguradora).
Future<void> openDocs(BuildContext context, {String party = ''}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DocsPage(party: party)));

/// Abre um documento guardado.
Future<void> openDoc(BuildContext context, StoredDoc d) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DocDetailPage(docId: d.id)));

IconData _icon(StoredDoc d) => switch (d.source) {
      DocSource.foto => Icons.photo_outlined,
      DocSource.xml => Icons.code,
      DocSource.pdf => Icons.picture_as_pdf_outlined,
      DocSource.manual => Icons.description_outlined,
    };

class DocsPage extends StatefulWidget {
  const DocsPage({super.key, this.party = ''});

  /// Só os documentos deste fornecedor/seguradora.
  final String party;

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  String _q = '';
  DocKind? _kind;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final base = widget.party.isEmpty ? store.docs : store.docsOfParty(widget.party);
    final list = base.where((d) {
      if (_kind != null && d.kind != _kind) return false;
      if (_q.isEmpty) return true;
      return d.party.toLowerCase().contains(_q) ||
          d.number.toLowerCase().contains(_q) ||
          d.items.any((i) =>
              i.description.toLowerCase().contains(_q) || i.code.toLowerCase().contains(_q));
    }).toList();
    final canRead = (gate.active(Mod.estoque) && gate.can(Perm.estoqueEditar)) ||
        (gate.active(Mod.financeiro) && gate.can(Perm.financeiroEditar));
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.party.isEmpty ? 'Documentos' : 'Documentos · ${widget.party}')),
      floatingActionButton: canRead && widget.party.isEmpty
          ? FloatingActionButton.extended(
              onPressed: () => readPurchaseNote(context),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Ler nota'),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar por fornecedor, número ou item',
            ),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            ChoiceChip(
              label: Text('Todos (${base.length})'),
              selected: _kind == null,
              onSelected: (_) => setState(() => _kind = null),
            ),
            for (final k in DocKind.values) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(
                    '${k == DocKind.notaCompra ? 'Notas de compra' : 'Orçamentos de seguradora'} (${base.where((d) => d.kind == k).length})'),
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
              ),
            ],
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.folder_open_outlined,
                  text:
                      'Toda nota de compra lida (foto, XML ou PDF) e todo orçamento de seguradora importado fica guardado aqui, ligado ao estoque, ao Financeiro e ao orçamento.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = list[i];
                    final claim = d.claimId.isEmpty ? null : store.claimById(d.claimId);
                    return ListTile(
                      leading: CircleAvatar(child: Icon(_icon(d))),
                      title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        if (d.number.isNotEmpty) d.number,
                        date(d.date),
                        if (d.items.isNotEmpty)
                          '${d.items.length} ${d.items.length == 1 ? 'item' : 'itens'}',
                        if (d.inStock) 'no estoque',
                        if (store.entryForDoc(d) != null) 'no Financeiro',
                        if (claim != null) claim.number,
                      ].join(' · ')),
                      trailing: gate.can(Perm.valoresVer) && d.total > 0
                          ? Text(money(d.total),
                              style: const TextStyle(fontWeight: FontWeight.w700))
                          : null,
                      onTap: () => openDoc(context, d),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class DocDetailPage extends StatelessWidget {
  const DocDetailPage({super.key, required this.docId});
  final String docId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final d = store.docById(docId);
    if (d == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Documento')),
          body: const EmptyState(
              icon: Icons.folder_off_outlined, text: 'Este documento foi excluído.'));
    }
    final t = Theme.of(context);
    final showMoney = gate.can(Perm.valoresVer);
    final entry = store.entryForDoc(d);
    final claim = d.claimId.isEmpty ? null : store.claimById(d.claimId);
    final canStock = gate.active(Mod.estoque) && gate.can(Perm.estoqueEditar);
    final canFinance = gate.active(Mod.financeiro) && gate.can(Perm.financeiroEditar);
    final isNote = d.kind == DocKind.notaCompra;
    StockItem? stockOf(DocItem i) {
      if (i.stockId.isEmpty) return null;
      for (final s in store.stock) {
        if (s.id == i.stockId) return s;
      }
      return null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(d.kind.label),
        actions: [
          if (gate.can(Perm.ajustes) || canStock || canFinance)
            IconButton(
              tooltip: 'Excluir documento',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirm(context, 'Excluir este documento?',
                    'O arquivo guardado é apagado. O que já entrou no estoque e no Financeiro continua como está.',
                    ok: 'Excluir', danger: true);
                if (!ok || !context.mounted) return;
                Navigator.pop(context);
                await store.removeDoc(d);
              },
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(d.title,
                  style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text([
                if (d.number.isNotEmpty) d.number,
                date(d.date),
                if (d.payment.isNotEmpty) d.payment,
                d.source.label,
              ].join(' · ')),
              if (showMoney && d.total > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(money(d.total),
                      style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
              Text('Guardado em ${date(d.createdAt)}', style: t.textTheme.bodySmall),
              const SizedBox(height: 12),
              if (d.file.isNotEmpty) _FileCard(doc: d),
              SectionCard(title: 'Ligado a', icon: Icons.link, children: [
                if (isNote) ...[
                  if (entry != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: Text('Financeiro: ${entry.description}'),
                      subtitle: Text(
                          '${date(entry.date)}${showMoney ? ' · ${money(entry.amount)}' : ''}'),
                      trailing: canFinance ? const Icon(Icons.chevron_right) : null,
                      onTap: !canFinance
                          ? null
                          : () async {
                              // edita uma cópia: "Cancelar" não mexe em nada
                              final r = await editFinanceEntry(
                                  context, FinanceEntry.fromJson(entry.toJson()));
                              if (r == null) return;
                              final i = store.entries.indexOf(entry);
                              if (i >= 0) store.entries[i] = r;
                              store.upsertEntry(r);
                            },
                    )
                  else
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: const Text('Sem lançamento no Financeiro'),
                      trailing: canFinance
                          ? FilledButton.tonal(
                              onPressed: () async {
                                await store.registerPurchase(d.toReceipt(),
                                    toFinance: true, doc: d);
                                if (context.mounted) toast(context, 'Gasto lançado no Financeiro.');
                              },
                              child: const Text('Lançar'),
                            )
                          : null,
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warehouse_outlined),
                    title: Text(d.inStock
                        ? 'Estoque: ${d.items.where((i) => i.stockId.isNotEmpty).length} de ${d.items.length} itens deram entrada'
                        : 'Não deu entrada no estoque'),
                    trailing: !d.inStock && d.items.isNotEmpty && canStock
                        ? FilledButton.tonal(
                            onPressed: () =>
                                reviewPurchaseNote(context, d.toReceipt(), doc: d),
                            child: const Text('Dar entrada'),
                          )
                        : null,
                  ),
                ],
                if (claim != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.car_crash_outlined),
                    title: Text('Orçamento ${claim.number} · ${claim.vehicle.title}'),
                    subtitle: Text(claim.status.label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openClaim(context, claim),
                  )
                else if (!isNote)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.car_crash_outlined),
                    title: Text('O orçamento deste documento foi excluído'),
                  ),
                if (d.party.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text('${isNote ? 'Fornecedor' : 'Seguradora'}: ${d.party}'),
                    subtitle: Text(
                        '${store.docsOfParty(d.party).length} ${store.docsOfParty(d.party).length == 1 ? 'documento' : 'documentos'} guardados'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openDocs(context, party: d.party),
                  ),
              ]),
              if (d.items.isNotEmpty)
                SectionCard(
                  title: 'Itens (${d.items.length})',
                  icon: Icons.list_alt,
                  children: [
                    for (final i in d.items)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(i.description),
                        subtitle: Text([
                          '${num2(i.qty)}${i.unit.isEmpty ? '' : ' ${i.unit.toLowerCase()}'}${showMoney && i.unitPrice > 0 ? ' × ${money(i.unitPrice)}' : ''}',
                          if (i.code.isNotEmpty) 'cód. ${i.code}',
                          if (stockOf(i) != null)
                            'estoque: ${stockOf(i)!.name} (tem ${stockOf(i)!.qtyLabel})',
                        ].join(' · ')),
                        trailing: showMoney ? Text(money(i.total)) : null,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.doc});
  final StoredDoc doc;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final file = store.docFile(doc);
    if (doc.isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showDialog<void>(
            context: context,
            builder: (ctx) => Dialog(
              insetPadding: const EdgeInsets.all(12),
              child: Stack(children: [
                InteractiveViewer(
                  maxScale: 6,
                  child: Image.file(file,
                      errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(32), child: Icon(Icons.broken_image))),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton.filledTonal(
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ]),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              child: Image.file(file,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  cacheWidth: 900,
                  errorBuilder: (_, __, ___) => const Center(
                      child: Text('Foto não encontrada neste aparelho'))),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          leading: Icon(_icon(doc)),
          title: Text(doc.source == DocSource.pdf ? 'PDF original guardado' : 'XML da NF-e guardado'),
          subtitle: Text(doc.source == DocSource.pdf
              ? 'Toque para abrir'
              : 'Vai junto no backup; os itens lidos estão abaixo'),
          trailing: doc.source == DocSource.pdf ? const Icon(Icons.open_in_new) : null,
          onTap: doc.source != DocSource.pdf ? null : () => _openPdf(context, file, doc),
        ),
      ),
    );
  }
}

Future<void> _openPdf(BuildContext context, File f, StoredDoc d) async {
  try {
    if (!await f.exists()) {
      if (context.mounted) toast(context, 'Arquivo não encontrado neste aparelho.');
      return;
    }
    final bytes = await f.readAsBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: d.title);
  } catch (e) {
    if (context.mounted) toast(context, 'Não foi possível abrir o PDF: $e');
  }
}

/// Usado pelo Estoque: histórico de entradas de um item, com a nota de cada
/// uma.
class StockInsList extends StatelessWidget {
  const StockInsList({super.key, required this.item});
  final StockItem item;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (item.ins.isEmpty) return const SizedBox.shrink();
    final showMoney = gate.can(Perm.valoresVer);
    final list = item.ins.reversed.take(8).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Entradas (compras)', style: Theme.of(context).textTheme.labelLarge),
      for (final i in list)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.south_west, size: 18),
          title: Text(
              '${date(i.date)} · +${qtyText(i.qty, item.unit)}${showMoney && i.unitCost > 0 ? ' · ${money(i.unitCost)}' : ''}'),
          subtitle: i.label.isEmpty ? null : Text(i.label),
          trailing: store.docById(i.docId) == null ? null : const Icon(Icons.receipt_long_outlined),
          onTap: store.docById(i.docId) == null
              ? null
              : () => openDoc(context, store.docById(i.docId)!),
        ),
    ]);
  }
}
