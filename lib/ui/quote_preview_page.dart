import 'dart:io';
import 'dart:ui' show FontFeature;

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
    const light = Color(0xFFE8F0F3);
    final small = TextStyle(fontSize: 12, color: Colors.grey.shade700);
    final statusColor = switch (c.status) {
      ClaimStatus.aprovado || ClaimStatus.emReparo => const Color(0xFF1B7F5B),
      ClaimStatus.concluido || ClaimStatus.entregue => primary,
      ClaimStatus.cancelado => Colors.red.shade700,
      ClaimStatus.aguardandoAprovacao => Colors.orange.shade700,
      _ => Colors.grey.shade700,
    };

    // ---- mesmas contas do PDF
    final labor = <String, (double, double)>{};
    void addLabor(String k, double v, double h) {
      if (v <= 0 && h <= 0) return;
      final o = labor[k] ?? (0.0, 0.0);
      labor[k] = (o.$1 + v, o.$2 + h);
    }

    var partsGross = 0.0, repairValue = 0.0, repairHours = 0.0, riValue = 0.0, riHours = 0.0;
    for (final it in items) {
      final v = itemValues(it, s);
      final hrs = it.perPiece ? 0.0 : it.laborHours;
      addLabor(it.laborType.label, v.labor, hrs);
      addLabor('Pintura', v.paintLabor + v.paintMaterial, it.perPiece ? 0 : it.paintHours);
      addLabor('Mão de obra por peça', v.pieceLabor, 0);
      addLabor('Serviços', v.services, 0);
      if (it.op == ItemOp.troca) partsGross += it.price * (it.qty <= 0 ? 1 : it.qty);
      if (it.op != ItemOp.troca && it.removeInstall && !it.alsoRepair) {
        riValue += v.labor;
        riHours += hrs;
      } else {
        repairValue += v.labor;
        repairHours += hrs;
      }
    }
    final laborTotal = labor.values.fold(0.0, (a, e) => a + e.$1);
    final laborList = labor.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    const laborColors = [
      Color(0xFF2F80ED), Color(0xFF27AE60), Color(0xFFE74C3C), Color(0xFFF2994A),
      Color(0xFF9B51E0), Color(0xFF56CCF2), Color(0xFF6FCF97), Color(0xFFBB6BD9), Color(0xFF828282),
    ];

    Widget band(String title) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(8)),
          child: Text(title.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .3)),
        );

    Widget cell(String label, String value, {double width = 150}) => SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10, right: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
              Text(value.trim().isEmpty ? '—' : value.trim()),
            ]),
          ),
        );

    Widget sumBox(String title, String value, String hours) => Container(
          width: 128,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: light, borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: small.copyWith(fontSize: 11)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (hours.isNotEmpty) Text(hours, style: small.copyWith(fontSize: 11)),
          ]),
        );

    final vehicleTitle = [c.vehicle.brand, c.vehicle.model, c.vehicle.year]
        .where((e) => e.trim().isNotEmpty)
        .join(' - ')
        .toUpperCase();

    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(4),
      child: DefaultTextStyle.merge(
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
                              fontSize: 20, fontWeight: FontWeight.w800, color: primary)),
                      if (s.shopDoc.isNotEmpty) Text('CNPJ/CPF: ${s.shopDoc}', style: small),
                      if (s.shopAddress.isNotEmpty) Text(s.shopAddress, style: small),
                      if (s.shopPhone.isNotEmpty || s.shopEmail.isNotEmpty)
                        Text([s.shopPhone, s.shopEmail].where((e) => e.isNotEmpty).join(' · '),
                            style: small),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(withPrices ? 'ORÇAMENTO' : 'LAUDO DE VISTORIA',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      Text('Nº ${c.number}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800, color: primary)),
                      Text('Emitido em ${dateTime(DateTime.now())}', style: small),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: statusColor, borderRadius: BorderRadius.circular(10)),
                        child: Text(c.status.label,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(color: primary, thickness: 1.5, height: 24),
              if (vehicleTitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(vehicleTitle,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              // ficha
              Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 2),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(children: [
                  cell('Placa', c.vehicle.plate),
                  cell('Cor', c.vehicle.color),
                  cell('Chassi', c.vehicle.chassis, width: 190),
                  cell('Quilometragem', c.vehicle.km),
                  cell('Combustível', c.vehicle.fuel),
                  if (hasInsurer) ...[
                    cell('Seguradora', c.insurerName),
                    cell('Sinistro', c.claimNumber),
                    cell('Apólice', c.policyNumber),
                    cell('Regulador / perito', c.regulatorName),
                    cell('Data do sinistro', date(c.accidentDate)),
                  ],
                  cell(c.type == ClaimType.terceiro ? 'Terceiro' : 'Cliente', c.customerName, width: 190),
                  cell('CPF/CNPJ', c.customerDoc),
                  cell('Telefone', c.customerPhone),
                  cell('E-mail', c.customerEmail, width: 190),
                  if (withPrices) ...[
                    cell('Mão de obra (funilaria)', '${money(s.rateFor(LaborType.funilaria))}/h'),
                    cell('Pintura', '${money(s.paintRate + s.paintMaterialRate)}/h'),
                    cell('Desconto', c.discountPct > 0 ? '${num2(c.discountPct)}%' : '—'),
                    if (hasInsurer)
                      cell('Franquia', c.deductible > 0 ? money(c.deductible) : '—')
                    else
                      cell('Atendimento', c.type.label),
                    cell(c.vehicle.fipeCode.isEmpty ? 'Valor FIPE' : 'Valor FIPE (${c.vehicle.fipeCode})',
                        c.vehicle.fipeValue > 0 ? money(c.vehicle.fipeValue) : '—'),
                  ],
                ]),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 8),
                _Legend(items: items, withPrices: withPrices, hours: s.showHours),
              ],
              if (c.description.trim().isNotEmpty) ...[
                band('Relato'),
                Text(c.description.trim()),
              ],
              if (c.damages.isNotEmpty || c.preDamages.isNotEmpty) ...[
                band('Avarias'),
                if (c.damages.isNotEmpty)
                  Text(c.damages.entries
                      .map((e) =>
                          '${regionById(e.key)?.label ?? e.key} (${(severityLabels[e.value] ?? '').toLowerCase()})')
                      .join(' · ')),
                if (c.preDamages.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  const Text('Pré-existentes (já estavam no veículo na entrada):',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(c.preDamages.entries
                      .map((e) =>
                          '${regionById(e.key)?.label ?? e.key} (${(severityLabels[e.value] ?? '').toLowerCase()})')
                      .join(' · ')),
                ],
              ],
              band('Peças e serviços (${items.length} ${items.length == 1 ? 'item' : 'itens'})'),
              if (items.isEmpty)
                const Text('Nenhum item lançado.')
              else
                _ItemsTable(items: items, settings: s, withPrices: withPrices),
              if (withPrices && items.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  sumBox('Troca / R&I', money(riValue), s.showHours ? '${num2(riHours)} h' : ''),
                  sumBox('Reparação', money(repairValue), s.showHours ? '${num2(repairHours)} h' : ''),
                  sumBox('Pintura', money(totals.paintLabor + totals.paintMaterial),
                      s.showHours ? '${num2(totals.paintHours)} h' : ''),
                  if (totals.pieceLabor > 0) sumBox('M.O. por peça', money(totals.pieceLabor), ''),
                  sumBox('Serviços', money(totals.services), ''),
                  sumBox('Peças', money(totals.parts), ''),
                  sumBox('Total', money(totals.total), ''),
                ]),
              ],
              if (withPrices) ...[
                band('Resumo geral'),
                Wrap(spacing: 20, runSpacing: 16, children: [
                  SizedBox(
                    width: 300,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Mão de obra', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      if (laborTotal > 0)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Row(children: [
                            for (final (i, e) in laborList.indexed)
                              Expanded(
                                flex: (e.value.$1 / laborTotal * 1000).round().clamp(1, 1000),
                                child: Container(height: 10, color: laborColors[i % laborColors.length]),
                              ),
                          ]),
                        ),
                      const SizedBox(height: 6),
                      for (final (i, e) in laborList.indexed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1.5),
                          child: Row(children: [
                            Icon(Icons.circle, size: 9, color: laborColors[i % laborColors.length]),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(
                                    '${e.key} (${num2(laborTotal > 0 ? e.value.$1 / laborTotal * 100 : 0)}%)')),
                            if (s.showHours && e.value.$2 > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text('${num2(e.value.$2)} h', style: small),
                              ),
                            Text(money(e.value.$1)),
                          ]),
                        ),
                      if (laborList.isEmpty) const Text('—'),
                    ]),
                  ),
                  SizedBox(
                    width: 220,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Peças', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      KeyValue('Bruto de peças', money(partsGross)),
                      KeyValue('Descontos',
                          partsGross - totals.parts > 0.004 ? '- ${money(partsGross - totals.parts)}' : money(0)),
                      KeyValue('Líquido de peças', money(totals.parts)),
                    ]),
                  ),
                  Container(
                    width: 280,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: light, borderRadius: BorderRadius.circular(6)),
                    child: Column(children: [
                      KeyValue('Peças', money(totals.parts)),
                      KeyValue('Mão de obra e serviços', money(laborTotal)),
                      if (totals.extra > 0) KeyValue('Outros custos', money(totals.extra)),
                      if (totals.discount > 0)
                        KeyValue('Desconto (${num2(c.discountPct)}%)', '- ${money(totals.discount)}'),
                      const Divider(),
                      KeyValue('TOTAL GERAL', money(totals.total), bold: true, color: primary),
                      if (c.type == ClaimType.seguradora || c.type == ClaimType.terceiro) ...[
                        if (c.type == ClaimType.seguradora)
                          KeyValue('Franquia (cliente)', money(totals.deductible)),
                        KeyValue('Seguradora', money(totals.insurerPays)),
                      ],
                    ]),
                  ),
                ]),
              ],
              band('Conclusão'),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Situação: ', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: c.status.label),
                if (c.approvedAt != null) ...[
                  const TextSpan(text: '  ·  Aprovado em: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(
                      text:
                          '${dateTime(c.approvedAt)}${c.approvedBy.isEmpty ? '' : ' por ${c.approvedBy}'}'),
                ],
                if (c.dueDate != null) ...[
                  const TextSpan(text: '  ·  Previsão de entrega: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: date(c.dueDate)),
                ],
              ])),
              if (!c.reception.isEmpty) ...[
                band('Checklist de entrada'),
                for (final l in receptionLines(c)) Text(l),
              ],
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4C4),
                  border: Border.all(color: const Color(0xFFE9C46A)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Observações gerais', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  if (withPrices) Text('• Validade do orçamento: ${s.budgetValidityDays} dias.'),
                  for (final l in s.budgetFooter.trim().split('\n'))
                    if (l.trim().isNotEmpty) Text('• ${l.trim()}'),
                ]),
              ),
              if (withPhotos && c.photos.isNotEmpty) ...[
                band('Fotos'),
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
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 40),
              Row(children: [
                Expanded(child: _Signature(s.shopName)),
                const SizedBox(width: 32),
                Expanded(child: _Signature(c.customerName.isEmpty ? 'Cliente' : c.customerName)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

const _head = TextStyle(
    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700);
const _num = TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]);

String _originShort(PartOrigin o) => switch (o) {
      PartOrigin.nenhuma => '',
      PartOrigin.original => 'Original',
      PartOrigin.genuina => 'Genuína',
      PartOrigin.paralela => 'Paralela',
      PartOrigin.usada => 'Usada',
    };

/// Tabela de peças e serviços com siglas (igual ao PDF).
class _ItemsTable extends StatelessWidget {
  const _ItemsTable(
      {required this.items, required this.settings, required this.withPrices});
  final List<BudgetItem> items;
  final Settings settings;
  final bool withPrices;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      return cons.maxWidth >= 560 ? _wide() : _narrow();
    });
  }

  Widget _code(BudgetItem it) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: brandSeed.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          opCode(it.op, it.labFlag, it.paintFlag,
              removeInstall: it.removeInstall, alsoRepair: it.alsoRepair),
          softWrap: false,
          style: const TextStyle(
              color: brandSeed, fontWeight: FontWeight.w800, fontSize: 12),
        ),
      );

  Widget _wide() {
    Widget cell(String t, {bool right = false, TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Text(t,
              textAlign: right ? TextAlign.right : TextAlign.left,
              style: style ?? _num),
        );
    final hours = settings.showHours;
    final laborCol = withPrices && !hours;
    final headers = [
      'Sigla', 'Peça / serviço', 'Origem', 'Qtd',
      if (hours) 'M.O. (h)',
      if (hours) 'Pint. (h)',
      if (laborCol) 'M.O.',
      if (withPrices) 'Peça/serv.',
      if (withPrices) 'Total',
    ];
    final widths = <TableColumnWidth>[
      const FixedColumnWidth(78),
      const FlexColumnWidth(),
      const FixedColumnWidth(78),
      const FixedColumnWidth(40),
      if (hours) const FixedColumnWidth(64),
      if (hours) const FixedColumnWidth(64),
      if (laborCol) const FixedColumnWidth(96),
      if (withPrices) const FixedColumnWidth(96),
      if (withPrices) const FixedColumnWidth(104),
    ];
    return Table(
      columnWidths: {for (final (i, w) in widths.indexed) i: w},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
          horizontalInside: BorderSide(color: Colors.grey.shade300, width: 0.6)),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: brandSeed),
          children: [
            for (final (i, h) in headers.indexed)
              cell(h, right: i >= 3, style: _head),
          ],
        ),
        for (final (i, it) in items.indexed)
          () {
            final v = itemValues(it, settings);
            final priced = it.op == ItemOp.troca || it.op == ItemOp.servico;
            return TableRow(
              decoration: BoxDecoration(
                  color: i.isOdd ? const Color(0xFFF3F6F8) : null),
              children: [
                Padding(
                    padding: const EdgeInsets.all(6),
                    child: Align(
                        alignment: Alignment.centerLeft, child: _code(it))),
                cell((it.parentId.isEmpty ? '' : '      ↳ ') +
                    (it.partNumber.isEmpty
                        ? it.description
                        : '${it.description}  (${it.partNumber})')),
                cell(it.op == ItemOp.troca ? _originShort(it.origin) : ''),
                cell(priced ? num2(it.qty <= 0 ? 1 : it.qty) : '', right: true),
                if (hours)
                  cell(it.laborHours > 0 ? num2(it.laborHours) : '',
                      right: true),
                if (hours)
                  cell(it.paintHours > 0 ? num2(it.paintHours) : '',
                      right: true),
                if (laborCol)
                  cell(_labor(v) > 0 ? money(_labor(v)) : '', right: true),
                if (withPrices)
                  cell(priced ? money(v.parts + v.services) : '', right: true),
                if (withPrices)
                  cell(money(v.total),
                      right: true,
                      style: _num.copyWith(fontWeight: FontWeight.w700)),
              ],
            );
          }(),
      ],
    );
  }

  Widget _narrow() {
    return Column(
      children: [
        for (final (i, it) in items.indexed)
          () {
            final v = itemValues(it, settings);
            final info = <String>[
              if (settings.showHours && it.laborHours > 0)
                'M.O. ${num2(it.laborHours)} h',
              if (settings.showHours && it.paintHours > 0)
                'Pint. ${num2(it.paintHours)} h',
              if (withPrices && !settings.showHours && _labor(v) > 0)
                'M.O. ${money(_labor(v))}',
              if (it.op == ItemOp.troca && it.origin != PartOrigin.nenhuma)
                _originShort(it.origin),
              if (withPrices &&
                  (it.op == ItemOp.troca || it.op == ItemOp.servico))
                'peça/serv. ${money(v.parts + v.services)}',
            ];
            return Container(
              color: i.isOdd ? const Color(0xFFF3F6F8) : null,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 64, child: Align(
                      alignment: Alignment.centerLeft, child: _code(it))),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            it.parentId.isEmpty
                                ? it.description
                                : '↳ ${it.description}',
                            style: TextStyle(
                                fontWeight: it.parentId.isEmpty
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                        if (info.isNotEmpty)
                          Text(info.join('  ·  '),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                  if (withPrices)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(money(v.total),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            );
          }(),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(
      {required this.items, required this.withPrices, required this.hours});
  final List<BudgetItem> items;
  final bool withPrices;
  final bool hours;

  @override
  Widget build(BuildContext context) {
    final entries = [
      ...legendFor(items),
      if (hours) ('M.O.', 'horas de mão de obra'),
      if (hours) ('Pint.', 'horas de pintura'),
      if (withPrices && !hours)
        ('M.O.', 'mão de obra: reparo, remoção e instalação e pintura'),
      if (withPrices) ('Peça/serv.', 'valor da peça nova ou do serviço'),
      ('PG', 'peça genuína'),
      ('PO', 'peça original'),
      ('PC', 'peça compatível'),
      ('PU', 'peça usada/reuso'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Legenda',
              style: TextStyle(color: brandSeed, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final (code, meaning) in entries)
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '$code  ',
                      style: const TextStyle(
                          color: brandSeed, fontWeight: FontWeight.w800)),
                  TextSpan(text: meaning),
                ]), style: const TextStyle(fontSize: 12)),
            ],
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


/// Mão de obra da linha em R\$ (reparo, R&I, pintura e material).
double _labor(ItemValues v) =>
    v.labor + v.paintLabor + v.paintMaterial + v.pieceLabor;
