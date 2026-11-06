import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'calc.dart';
import 'format.dart';
import 'models.dart';
import 'seed.dart';
import 'store.dart';
import 'ui/widgets.dart' show shareOrigin, toast;

/// Remove caracteres fora do Latin-1 (fonte padrão do PDF).
String _t(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x2014 || r == 0x2013) {
      b.write('-');
    } else if (r == 0x2026) {
      b.write('...');
    } else if (r == 0x203A) {
      b.write('>');
    } else if (r < 256) {
      b.writeCharCode(r);
    } else {
      b.write('?');
    }
  }
  return b.toString();
}

Future<Uint8List> buildClaimPdf(AppStore store, Claim c,
    {bool withPhotos = true, bool withPrices = true}) async {
  final s = store.settings;
  final totals = computeTotals(c, s);
  final doc = pw.Document(
    title: _t('Orçamento ${c.number}'),
    author: _t(s.shopName),
  );
  const primary = PdfColor.fromInt(0xFF0E5A73);
  const light = PdfColor.fromInt(0xFFE8F0F3);
  final small = const pw.TextStyle(fontSize: 8);
  final normal = const pw.TextStyle(fontSize: 9);
  final bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
  final hasInsurer = c.type != ClaimType.particular;

  // fotos
  final images = <(pw.MemoryImage, String)>[];
  if (withPhotos) {
    for (final p in c.photos.take(24)) {
      final f = store.photoFile(p);
      if (await f.exists()) {
        try {
          images.add((
            pw.MemoryImage(await f.readAsBytes()),
            _t('${p.category.label}${p.caption.isEmpty ? '' : ' - ${p.caption}'}')
          ));
        } catch (_) {}
      }
    }
  }

  pw.Widget totalRow(String k, String v, {bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(children: [
          pw.Expanded(
              child: pw.Text(_t(k), style: strong ? bold : normal)),
          pw.Text(_t(v),
              style: strong
                  ? pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: primary)
                  : normal),
        ]),
      );

  final items = c.items.where((e) => e.approved).toList();
  const accent = PdfColor.fromInt(0xFF1B7F5B);
  const amber = PdfColor.fromInt(0xFFFFF4C4);
  const amberLine = PdfColor.fromInt(0xFFE9C46A);
  final statusColor = switch (c.status) {
    ClaimStatus.aprovado || ClaimStatus.emReparo => accent,
    ClaimStatus.concluido || ClaimStatus.entregue => primary,
    ClaimStatus.cancelado => PdfColors.red700,
    ClaimStatus.aguardandoAprovacao => PdfColors.orange700,
    _ => PdfColors.grey700,
  };

  // ---- blocos de rótulo em cima / valor embaixo (estilo ficha)
  pw.Widget cell(String label, String value, {int flex = 1}) => pw.Expanded(
        flex: flex,
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(right: 6, bottom: 6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(_t(label),
                  style: pw.TextStyle(
                      fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
              pw.SizedBox(height: 1),
              pw.Text(_t(value.trim().isEmpty ? '-' : value.trim()),
                  style: const pw.TextStyle(fontSize: 9), maxLines: 3),
            ],
          ),
        ),
      );
  pw.Widget cells(List<pw.Widget> c) =>
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: c);

  pw.Widget band(String title) => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: pw.BoxDecoration(color: primary, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Text(_t(title.toUpperCase()),
            style: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
      );

  // ---- operações de cada item: "T  R&I 0,5  R 2,0  P 3,0"
  String ops(BudgetItem it) {
    if (it.op == ItemOp.servico) return 'S';
    String h(double v) => s.showHours && !it.perPiece && v > 0 ? ' ${num2(v)}' : '';
    final out = <String>[];
    if (it.op == ItemOp.troca) {
      out.add('T');
      if (it.laborHours > 0) out.add('R&I${h(it.laborHours)}');
    } else if (it.hasLabor) {
      if (it.removeInstall && !it.alsoRepair) {
        out.add('R&I${h(it.laborHours)}');
      } else if (it.removeInstall) {
        out.add('R&I+R${h(it.laborHours)}');
      } else {
        out.add('R${h(it.laborHours)}');
      }
    }
    if (it.hasPaint) out.add('P${h(it.paintHours)}');
    return out.isEmpty ? 'R' : out.join('  ');
  }

  String partType(PartOrigin o) => switch (o) {
        PartOrigin.genuina => 'PG',
        PartOrigin.original => 'PO',
        PartOrigin.paralela => 'PC',
        PartOrigin.usada => 'PU',
        PartOrigin.nenhuma => '',
      };

  // ---- mão de obra por tipo (com % e horas) e peças
  final labor = <String, (double, double)>{}; // tipo -> (valor, horas)
  void addLabor(String k, double v, double hrs) {
    if (v <= 0 && hrs <= 0) return;
    final o = labor[k] ?? (0.0, 0.0);
    labor[k] = (o.$1 + v, o.$2 + hrs);
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
    if (it.op == ItemOp.troca || (it.removeInstall && !it.alsoRepair)) {
      riValue += v.labor;
      riHours += hrs;
    } else {
      repairValue += v.labor;
      repairHours += hrs;
    }
  }
  final laborTotal = labor.values.fold(0.0, (a, e) => a + e.$1);
  const laborColors = [
    PdfColor.fromInt(0xFF2F80ED), PdfColor.fromInt(0xFF27AE60), PdfColor.fromInt(0xFFE74C3C),
    PdfColor.fromInt(0xFFF2994A), PdfColor.fromInt(0xFF9B51E0), PdfColor.fromInt(0xFF56CCF2),
    PdfColor.fromInt(0xFF6FCF97), PdfColor.fromInt(0xFFBB6BD9), PdfColor.fromInt(0xFF828282),
  ];
  final laborList = labor.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));

  pw.Widget summaryBox(String title, String value, String hours) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 4),
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: pw.BoxDecoration(color: light, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(_t(title), style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            pw.Text(_t(value), style: bold),
            if (hours.isNotEmpty) pw.Text(_t(hours), style: small),
          ]),
        ),
      );

  final legendLine = pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Wrap(spacing: 12, runSpacing: 2, children: [
      for (final (code, meaning) in [
        ('T', 'troca'),
        ('R&I', 'remoção e instalação'),
        ('R', 'reparação'),
        ('P', 'pintura'),
        ('S', 'serviço'),
        ('PG', 'peça genuína'),
        ('PO', 'peça original'),
        ('PC', 'peça compatível'),
        ('PU', 'peça usada/reuso'),
      ])
        pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(
                text: '$code ',
                style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: primary)),
            pw.TextSpan(text: _t(meaning), style: const pw.TextStyle(fontSize: 7.5)),
          ]),
        ),
    ]),
  );

  final vehicleTitle = [
    c.vehicle.brand,
    c.vehicle.model,
    c.vehicle.year,
  ].where((e) => e.trim().isNotEmpty).join(' - ').toUpperCase();
  final isThird = c.type == ClaimType.terceiro;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 34),
      header: (ctx) => pw.Column(children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_t(s.shopName),
                      style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: primary)),
                  if (s.shopDoc.isNotEmpty) pw.Text(_t('CNPJ/CPF: ${s.shopDoc}'), style: small),
                  if (s.shopAddress.isNotEmpty) pw.Text(_t(s.shopAddress), style: small),
                  pw.Text(_t([s.shopPhone, s.shopEmail].where((e) => e.isNotEmpty).join(' - ')),
                      style: small),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(withPrices ? 'ORÇAMENTO' : 'LAUDO DE VISTORIA',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text(_t('Nº ${c.number}'),
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primary)),
                pw.Text(_t('Emitido em ${dateTime(DateTime.now())}'), style: small),
                pw.SizedBox(height: 3),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: pw.BoxDecoration(
                      color: statusColor, borderRadius: pw.BorderRadius.circular(8)),
                  child: pw.Text(_t(c.status.label),
                      style: pw.TextStyle(
                          fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                ),
              ],
            ),
          ],
        ),
        pw.Divider(color: primary, thickness: 1.2),
      ]),
      footer: (ctx) => pw.Row(children: [
        pw.Expanded(
            child: pw.Text(
                _t('Status: ${c.status.label} | Gerado em ${dateTime(DateTime.now())} pelo Funilar | ${s.shopName} - ${c.number}'),
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600))),
        pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      ]),
      build: (ctx) => [
        // ---- veículo em destaque
        if (vehicleTitle.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text(_t(vehicleTitle),
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
        // ---- ficha: veículo, seguro, cliente/terceiro, oficina
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(8, 8, 2, 2),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(children: [
            cells([
              cell('Placa', c.vehicle.plate),
              cell('Cor', c.vehicle.color),
              cell('Chassi', c.vehicle.chassis, flex: 2),
              cell('Quilometragem', c.vehicle.km),
              cell('Combustível', c.vehicle.fuel),
            ]),
            if (hasInsurer)
              cells([
                cell('Seguradora', c.insurerName),
                cell('Sinistro', c.claimNumber),
                cell('Apólice', c.policyNumber),
                cell('Regulador / perito', c.regulatorName),
                cell('Data do sinistro', date(c.accidentDate)),
              ]),
            cells([
              cell(isThird ? 'Terceiro' : 'Cliente', c.customerName, flex: 2),
              cell('CPF/CNPJ', c.customerDoc),
              cell('Telefone', c.customerPhone),
              cell('E-mail', c.customerEmail),
            ]),
            if (withPrices)
              cells([
                cell('Mão de obra (funilaria)', '${money(s.rateFor(LaborType.funilaria))}/h'),
                cell('Pintura', '${money(s.paintRate + s.paintMaterialRate)}/h'),
                cell('Desconto', c.discountPct > 0 ? '${num2(c.discountPct)}%' : '-'),
                cell(hasInsurer ? 'Franquia' : 'Atendimento',
                    hasInsurer ? (c.deductible > 0 ? money(c.deductible) : '-') : c.type.label),
                cell(
                    c.vehicle.fipeCode.isEmpty ? 'Valor FIPE' : 'Valor FIPE (${c.vehicle.fipeCode})',
                    c.vehicle.fipeValue > 0 ? money(c.vehicle.fipeValue) : '-'),
              ]),
          ]),
        ),
        pw.SizedBox(height: 6),
        legendLine,
        if (c.description.trim().isNotEmpty) ...[
          band('Relato'),
          pw.Text(_t(c.description.trim()), style: normal),
        ],
        if (c.damages.isNotEmpty || c.preDamages.isNotEmpty) ...[
          band('Avarias'),
          if (c.damages.isNotEmpty)
            pw.Wrap(spacing: 10, runSpacing: 2, children: [
              for (final e in c.damages.entries)
                pw.Text(_t('- ${regionById(e.key)?.label ?? e.key} (${severityLabels[e.value] ?? ''})'),
                    style: normal),
            ]),
          if (c.preDamages.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text('Pré-existentes (já estavam no veículo na entrada):', style: bold),
            pw.Wrap(spacing: 10, runSpacing: 2, children: [
              for (final e in c.preDamages.entries)
                pw.Text(_t('- ${regionById(e.key)?.label ?? e.key} (${severityLabels[e.value] ?? ''})'),
                    style: normal),
            ]),
          ],
        ],
        // ---- itens
        band('Peças e serviços (${items.length} ${items.length == 1 ? 'item' : 'itens'})'),
        if (items.isEmpty)
          pw.Text('Nenhum item lançado.', style: normal)
        else
          pw.TableHelper.fromTextArray(
            headers: [
              'Operações',
              'Qtd',
              'Código',
              'Tipo',
              'Peça / serviço',
              'Fornec.',
              if (withPrices) 'M.O.',
              if (withPrices) 'Peça/serv.',
              if (withPrices) 'Total',
            ],
            data: [
              for (final it in items)
                () {
                  final v = itemValues(it, s);
                  final priced = it.op == ItemOp.troca || it.op == ItemOp.servico;
                  final l = v.labor + v.paintLabor + v.paintMaterial + v.pieceLabor;
                  return <String>[
                    _t(ops(it)),
                    priced ? num2(it.qty <= 0 ? 1 : it.qty) : '1',
                    _t(it.partNumber),
                    it.op == ItemOp.troca ? partType(it.origin) : '',
                    _t((it.parentId.isEmpty ? '' : '    > ') +
                        it.description +
                        (it.discountPct > 0 ? '  (desc. ${num2(it.discountPct)}%)' : '')),
                    _t(it.op == ItemOp.troca
                        ? (it.supplier.trim().isEmpty ? 'Oficina' : it.supplier.trim())
                        : ''),
                    if (withPrices) l > 0 ? _t(money(l)) : '-',
                    if (withPrices) priced ? _t(money(v.parts + v.services)) : '-',
                    if (withPrices) _t(money(v.total)),
                  ];
                }(),
            ],
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
            ),
            headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: primary),
            headerDecoration: const pw.BoxDecoration(color: light),
            headerAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7FAFB)),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignments: {
              1: pw.Alignment.center,
              if (withPrices) ...{6: pw.Alignment.centerRight, 7: pw.Alignment.centerRight, 8: pw.Alignment.centerRight},
            },
            cellAlignments: {
              1: pw.Alignment.center,
              if (withPrices) ...{6: pw.Alignment.centerRight, 7: pw.Alignment.centerRight, 8: pw.Alignment.centerRight},
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(74),
              1: const pw.FixedColumnWidth(22),
              2: const pw.FixedColumnWidth(48),
              3: const pw.FixedColumnWidth(24),
              4: const pw.FlexColumnWidth(4),
              5: const pw.FixedColumnWidth(46),
              if (withPrices) ...{
                6: const pw.FixedColumnWidth(52),
                7: const pw.FixedColumnWidth(54),
                8: const pw.FixedColumnWidth(56),
              },
            },
          ),
        // ---- faixa de subtotais por operação
        if (withPrices && items.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Row(children: [
            summaryBox('Troca / R&I', money(riValue), s.showHours ? '${num2(riHours)} h' : ''),
            summaryBox('Reparação', money(repairValue), s.showHours ? '${num2(repairHours)} h' : ''),
            summaryBox('Pintura', money(totals.paintLabor + totals.paintMaterial),
                s.showHours ? '${num2(totals.paintHours)} h' : ''),
            if (totals.pieceLabor > 0) summaryBox('M.O. por peça', money(totals.pieceLabor), ''),
            summaryBox('Serviços', money(totals.services), ''),
            summaryBox('Peças', money(totals.parts), ''),
            summaryBox('Total', money(totals.total), ''),
          ]),
        ],
        // ---- resumo geral: mão de obra por tipo, peças e total
        if (withPrices) ...[
          band('Resumo geral'),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 5,
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Mão de obra', style: bold),
                  pw.SizedBox(height: 4),
                  if (laborTotal > 0)
                    pw.ClipRRect(
                      horizontalRadius: 3,
                      verticalRadius: 3,
                      child: pw.Row(children: [
                        for (final (i, e) in laborList.indexed)
                          pw.Expanded(
                            flex: (e.value.$1 / laborTotal * 1000).round().clamp(1, 1000),
                            child: pw.Container(
                                height: 8,
                                decoration: pw.BoxDecoration(color: laborColors[i % laborColors.length])),
                          ),
                      ]),
                    ),
                  pw.SizedBox(height: 4),
                  for (final (i, e) in laborList.indexed)
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
                      child: pw.Row(children: [
                        pw.Container(
                            width: 6,
                            height: 6,
                            decoration: pw.BoxDecoration(
                                color: laborColors[i % laborColors.length],
                                borderRadius: pw.BorderRadius.circular(3))),
                        pw.SizedBox(width: 4),
                        pw.Expanded(
                            child: pw.Text(
                                _t('${e.key} (${num2(laborTotal > 0 ? e.value.$1 / laborTotal * 100 : 0)}%)'),
                                style: normal)),
                        if (s.showHours && e.value.$2 > 0)
                          pw.SizedBox(width: 34, child: pw.Text(_t('${num2(e.value.$2)} h'), style: small)),
                        pw.SizedBox(
                            width: 62,
                            child: pw.Text(_t(money(e.value.$1)),
                                style: normal, textAlign: pw.TextAlign.right)),
                      ]),
                    ),
                  if (laborList.isEmpty) pw.Text('-', style: normal),
                ]),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                flex: 4,
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Peças', style: bold),
                  pw.SizedBox(height: 4),
                  totalRow('Bruto de peças', money(partsGross)),
                  totalRow('Descontos', partsGross - totals.parts > 0.004 ? '- ${money(partsGross - totals.parts)}' : money(0)),
                  totalRow('Líquido de peças', money(totals.parts)),
                ]),
              ),
              pw.SizedBox(width: 10),
              pw.Container(
                width: 170,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(color: light, borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Column(children: [
                  totalRow('Peças', money(totals.parts)),
                  totalRow('Mão de obra e serviços', money(laborTotal)),
                  if (totals.extra > 0) totalRow('Outros custos', money(totals.extra)),
                  if (totals.discount > 0)
                    totalRow('Desconto (${num2(c.discountPct)}%)', '- ${money(totals.discount)}'),
                  pw.Divider(thickness: 0.6),
                  totalRow('TOTAL GERAL', money(totals.total), strong: true),
                  if (c.type == ClaimType.seguradora || c.type == ClaimType.terceiro) ...[
                    if (c.type == ClaimType.seguradora)
                      totalRow('Franquia (cliente)', money(totals.deductible)),
                    totalRow('Seguradora', money(totals.insurerPays)),
                  ],
                ]),
              ),
            ],
          ),
        ],
        // ---- conclusão e últimos registros
        band('Conclusão'),
        pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(text: 'Situação: ', style: bold),
            pw.TextSpan(text: _t(c.status.label), style: normal),
            if (c.approvedAt != null) ...[
              pw.TextSpan(text: '  |  Aprovado em: ', style: bold),
              pw.TextSpan(
                  text: _t('${dateTime(c.approvedAt)}${c.approvedBy.isEmpty ? '' : ' por ${c.approvedBy}'}'),
                  style: normal),
            ],
            if (c.dueDate != null) ...[
              pw.TextSpan(text: '  |  Previsão de entrega: ', style: bold),
              pw.TextSpan(text: _t(date(c.dueDate)), style: normal),
            ],
          ]),
        ),
        // ---- observações gerais
        pw.SizedBox(height: 10),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: amber,
            border: pw.Border.all(color: amberLine, width: 0.8),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Observações gerais', style: bold),
            pw.SizedBox(height: 3),
            if (withPrices)
              pw.Text(_t('- Validade do orçamento: ${s.budgetValidityDays} dias.'), style: normal),
            if (s.budgetFooter.trim().isNotEmpty)
              for (final l in s.budgetFooter.trim().split('\n'))
                if (l.trim().isNotEmpty) pw.Text(_t('- ${l.trim()}'), style: normal),
          ]),
        ),
        // checklist de entrada no fim do documento
        if (!c.reception.isEmpty) ...[
          band('Checklist de entrada'),
          for (final l in receptionLines(c)) pw.Text(_t(l), style: normal),
        ],
        if (images.isNotEmpty) ...[
          band('Fotos'),
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (img, cap) in images)
                pw.Container(
                  width: 170,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(height: 120, width: 170, child: pw.Image(img, fit: pw.BoxFit.cover)),
                      pw.Text(cap, style: small, maxLines: 2),
                    ],
                  ),
                ),
            ],
          ),
        ],
        pw.SizedBox(height: 36),
        pw.Row(children: [
          pw.Expanded(child: _signature(_t(s.shopName))),
          pw.SizedBox(width: 40),
          pw.Expanded(child: _signature(_t(c.customerName.isEmpty ? 'Cliente' : c.customerName))),
        ]),
      ],
    ),
  );
  return doc.save();
}


pw.Widget _signature(String name) => pw.Column(children: [
      pw.Divider(thickness: 0.6),
      pw.Text(name, style: const pw.TextStyle(fontSize: 8)),
    ]);

/// Nome do arquivo: só o modelo e a placa (ex.: "Gol 1.0 ABC-1D23.pdf").
String pdfFileName(Claim c) {
  final base = [c.vehicle.model.trim(), c.vehicle.plate.trim().toUpperCase()]
      .where((e) => e.isNotEmpty)
      .join(' ')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${base.isEmpty ? c.number : base}.pdf';
}

enum PdfAction { print, share, save }

/// Gera o PDF só no momento de imprimir, compartilhar ou salvar.
Future<void> exportClaimPdf(
  BuildContext context,
  AppStore store,
  Claim c,
  PdfAction action, {
  bool withPhotos = true,
  bool withPrices = true,
}) async {
  final origin = shareOrigin(context);
  final name = pdfFileName(c);
  try {
    final bytes = await buildClaimPdf(store, c,
        withPhotos: withPhotos, withPrices: withPrices);
    switch (action) {
      case PdfAction.print:
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
      case PdfAction.share:
        await Printing.sharePdf(bytes: bytes, filename: name, bounds: origin);
      case PdfAction.save:
        final loc = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'PDF', extensions: ['pdf'])
          ],
        );
        if (loc == null) return;
        await File(loc.path).writeAsBytes(bytes, flush: true);
        if (context.mounted) toast(context, 'PDF salvo em ${loc.path}');
    }
    c.timeline.add(TimelineEvent(
        text: 'PDF ${withPrices ? 'do orçamento' : 'de vistoria'} gerado'));
    store.touch(c);
  } catch (e) {
    if (context.mounted) toast(context, 'Falha ao gerar PDF: $e');
  }
}
