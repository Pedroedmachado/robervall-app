import 'dart:io';

import 'package:flutter/material.dart';

import '../calc.dart';
import '../format.dart';
import '../models.dart';
import '../pdf_report.dart';
import '../seed.dart';
import '../theme.dart';
import 'widgets.dart';

/// Pré-visualização do orçamento dentro do app (sem gerar PDF).
/// O PDF só é criado quando a pessoa toca em imprimir, compartilhar ou salvar.
class QuotePreviewPage extends StatefulWidget {
  const QuotePreviewPage({super.key, required this.claimId});
  final String claimId;

  @override
  State<QuotePreviewPage> createState() => _QuotePreviewPageState();
}

class _QuotePreviewPageState extends State<QuotePreviewPage> {
  bool _prices = true;
  bool? _photos;
  bool _busy = false;

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  Future<void> _export(PdfAction action) async {
    final store = StoreScope.read(context);
    final c = store.claimById(widget.claimId);
    if (c == null) return;
    setState(() => _busy = true);
    await exportClaimPdf(context, store, c, action,
        withPhotos: _photos ?? c.photos.isNotEmpty, withPrices: _prices);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = store.claimById(widget.claimId);
    if (c == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const EmptyState(
              icon: Icons.delete_outline, text: 'Registro não encontrado.'));
    }
    final photos = (_photos ?? c.photos.isNotEmpty) && c.photos.isNotEmpty;
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_prices ? 'Orçamento' : 'Vistoria'} ${c.number}'),
      ),
      body: Column(
        children: [
          Material(
            color: t.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Com valores')),
                      ButtonSegment(value: false, label: Text('Sem valores')),
                    ],
                    selected: {_prices},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _prices = s.first),
                  ),
                  if (c.photos.isNotEmpty)
                    FilterChip(
                      label: Text('Fotos (${c.photos.length})'),
                      selected: photos,
                      onSelected: (v) => setState(() => _photos = v),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              color: t.brightness == Brightness.light
                  ? const Color(0xFFE6E9ED)
                  : const Color(0xFF2B2F33),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Theme(
                        data: buildTheme(Brightness.light),
                        child: _Paper(
                            claim: c, withPrices: _prices, withPhotos: photos),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Material(
        color: t.colorScheme.surfaceContainer,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _export(PdfAction.print),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Imprimir'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _mobile
                      ? FilledButton.icon(
                          onPressed:
                              _busy ? null : () => _export(PdfAction.share),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Compartilhar'),
                        )
                      : FilledButton.icon(
                          onPressed:
                              _busy ? null : () => _export(PdfAction.save),
                          icon: const Icon(Icons.save_alt),
                          label: const Text('Salvar PDF'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper(
      {required this.claim, required this.withPrices, required this.withPhotos});
  final Claim claim;
  final bool withPrices;
  final bool withPhotos;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final c = claim;
    final totals = computeTotals(c, s);
    final items = c.items.where((e) => e.approved).toList();
    final hasInsurer = c.type != ClaimType.particular;
    const primary = brandSeed;
    final small = TextStyle(fontSize: 12, color: Colors.grey.shade700);

    Widget box(String title, List<Widget> children) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...children,
            ],
          ),
        );

    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: '$k: ',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: v.isEmpty ? '—' : v),
          ])),
        );

    Widget pair(Widget a, Widget b) => LayoutBuilder(
          builder: (context, cons) => cons.maxWidth < 520
              ? Column(children: [a, const SizedBox(height: 8), b])
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: a),
                      const SizedBox(width: 8),
                      Expanded(child: b),
                    ],
                  ),
                ),
        );

    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(4),
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.3),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // cabeçalho
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                spacing: 16,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.shopName,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: primary)),
                      if (s.shopDoc.isNotEmpty)
                        Text('CNPJ/CPF: ${s.shopDoc}', style: small),
                      if (s.shopAddress.isNotEmpty)
                        Text(s.shopAddress, style: small),
                      if (s.shopPhone.isNotEmpty || s.shopEmail.isNotEmpty)
                        Text(
                            [s.shopPhone, s.shopEmail]
                                .where((e) => e.isNotEmpty)
                                .join(' · '),
                            style: small),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(withPrices ? 'ORÇAMENTO' : 'LAUDO DE VISTORIA',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      Text('Nº ${c.number}',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: primary)),
                      Text('Emissão: ${date(DateTime.now())}', style: small),
                      Text('Status: ${c.status.label}', style: small),
                    ],
                  ),
                ],
              ),
              const Divider(color: primary, thickness: 1.5, height: 24),
              pair(
                box('Cliente', [
                  kv('Nome', c.customerName),
                  kv('Telefone', c.customerPhone),
                  kv('CPF/CNPJ', c.customerDoc),
                  if (c.customerEmail.isNotEmpty) kv('E-mail', c.customerEmail),
                  kv('Atendimento', c.type.label),
                ]),
                box('Veículo', [
                  kv('Placa', c.vehicle.plate),
                  kv('Veículo', c.vehicle.title),
                  kv('Cor', c.vehicle.color),
                  kv('Chassi', c.vehicle.chassis),
                  kv('Km', c.vehicle.km),
                  if (c.vehicle.fipeValue > 0)
                    kv('FIPE', money(c.vehicle.fipeValue)),
                ]),
              ),
              if (hasInsurer) ...[
                const SizedBox(height: 8),
                box('Seguradora / regulação', [
                  kv('Seguradora', c.insurerName),
                  kv('Sinistro', c.claimNumber),
                  kv('Apólice', c.policyNumber),
                  kv('Regulador', c.regulatorName),
                  kv('Data do sinistro', date(c.accidentDate)),
                  kv(
                      'Aprovação',
                      c.approvedAt == null
                          ? 'pendente'
                          : '${date(c.approvedAt)}${c.approvedBy.isEmpty ? '' : ' por ${c.approvedBy}'}'),
                ]),
              ],
              if (c.description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                box('Relato', [Text(c.description.trim())]),
              ],
              if (c.damages.isNotEmpty) ...[
                const SizedBox(height: 8),
                box('Avarias constatadas', [
                  Text(c.damages.entries
                      .map((e) =>
                          '${regionById(e.key)?.label ?? e.key} (${(severityLabels[e.value] ?? '').toLowerCase()})')
                      .join(' · ')),
                ]),
              ],
              const SizedBox(height: 16),
              const Text('Peças e serviços',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: primary)),
              const SizedBox(height: 6),
              if (items.isEmpty)
                const Text('Nenhum item lançado.')
              else
                for (final (i, it) in items.indexed)
                  _ItemLine(
                    item: it,
                    values: itemValues(it, s),
                    withPrices: withPrices,
                    shaded: i.isOdd,
                  ),
              if (withPrices) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0F3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        KeyValue('Peças', money(totals.parts)),
                        KeyValue('Mão de obra (${num2(totals.laborHours)} h)',
                            money(totals.labor)),
                        KeyValue('Pintura (${num2(totals.paintHours)} h)',
                            money(totals.paintLabor)),
                        KeyValue('Material de pintura',
                            money(totals.paintMaterial)),
                        KeyValue('Serviços', money(totals.services)),
                        if (totals.extra > 0)
                          KeyValue('Outros custos', money(totals.extra)),
                        if (totals.discount > 0)
                          KeyValue('Desconto (${num2(c.discountPct)}%)',
                              '- ${money(totals.discount)}'),
                        const Divider(),
                        KeyValue('TOTAL', money(totals.total),
                            bold: true, color: primary),
                        if (c.type == ClaimType.seguradora ||
                            c.type == ClaimType.terceiro) ...[
                          if (c.type == ClaimType.seguradora)
                            KeyValue('Franquia (cliente)',
                                money(totals.deductible)),
                          KeyValue('Seguradora', money(totals.insurerPays)),
                          KeyValue('Cliente', money(totals.customerPays)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (c.dueDate != null)
                  Text('Previsão de entrega: ${date(c.dueDate)}'),
                Text('Validade do orçamento: ${s.budgetValidityDays} dias'),
              ],
              if (withPhotos) ...[
                const SizedBox(height: 16),
                const Text('Fotos',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: primary)),
                const SizedBox(height: 6),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  children: [
                    for (final p in c.photos.take(24))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          store.photoFile(p),
                          fit: BoxFit.cover,
                          cacheWidth: 300,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image),
                        ),
                      ),
                  ],
                ),
              ],
              if (s.budgetFooter.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(s.budgetFooter.trim(), style: small),
              ],
              const SizedBox(height: 40),
              Row(children: [
                Expanded(child: _Signature(s.shopName)),
                const SizedBox(width: 32),
                Expanded(
                    child: _Signature(
                        c.customerName.isEmpty ? 'Cliente' : c.customerName)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine(
      {required this.item,
      required this.values,
      required this.withPrices,
      required this.shaded});
  final BudgetItem item;
  final ItemValues values;
  final bool withPrices;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final it = item;
    final qty = it.qty <= 0 ? 1.0 : it.qty;
    final extra = <String>[
      if (it.partNumber.isNotEmpty) it.partNumber,
      if (it.op == ItemOp.troca && it.origin != PartOrigin.nenhuma)
        it.origin.label,
      if (withPrices && (it.op == ItemOp.troca || it.op == ItemOp.servico))
        '${qty == 1 ? '' : '${num2(qty)} × '}${money(it.price)}',
    ];
    return Container(
      color: shaded ? const Color(0xFFF3F6F8) : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.description,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  [
                    opDetails(it.op, it.laborHours, it.paintHours).join(' · '),
                    ...extra,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          if (withPrices)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(money(values.total),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class _Signature extends StatelessWidget {
  const _Signature(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Divider(color: Colors.black54),
        Text(name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12)),
      ]);
}
