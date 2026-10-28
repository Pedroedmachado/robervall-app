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

  pw.Widget box(String title, List<pw.Widget> children) => pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(_t(title),
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: primary)),
            pw.SizedBox(height: 4),
            ...children,
          ],
        ),
      );

  pw.Widget kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 1.5),
        child: pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(text: _t('$k: '), style: bold),
            pw.TextSpan(text: _t(v.isEmpty ? '-' : v), style: normal),
          ]),
        ),
      );

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

  final legendBox = pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Legenda',
                    style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: primary)),
                pw.SizedBox(height: 3),
                pw.Wrap(
                  spacing: 14,
                  runSpacing: 3,
                  children: [
                    for (final (code, meaning) in [
                      ...legendFor(items),
                      ('M.O.', 'horas de mão de obra'),
                      ('Pint.', 'horas de pintura'),
                      if (withPrices)
                        ('Peça/serv.', 'valor da peça nova ou do serviço'),
                    ])
                      pw.RichText(
                        text: pw.TextSpan(children: [
                          pw.TextSpan(
                              text: '$code  ',
                              style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: primary)),
                          pw.TextSpan(
                              text: _t(meaning),
                              style: const pw.TextStyle(fontSize: 8)),
                        ]),
                      ),
                  ],
                ),
              ],
            ),
          );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
      header: (ctx) => pw.Column(children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_t(s.shopName),
                      style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: primary)),
                  if (s.shopDoc.isNotEmpty)
                    pw.Text(_t('CNPJ/CPF: ${s.shopDoc}'), style: small),
                  if (s.shopAddress.isNotEmpty)
                    pw.Text(_t(s.shopAddress), style: small),
                  pw.Text(
                      _t([s.shopPhone, s.shopEmail]
                          .where((e) => e.isNotEmpty)
                          .join(' - ')),
                      style: small),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(withPrices ? 'ORÇAMENTO' : 'LAUDO DE VISTORIA',
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text(_t('Nº ${c.number}'),
                    style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: primary)),
                pw.Text(_t('Emissão: ${date(DateTime.now())}'), style: small),
                pw.Text(_t('Status: ${c.status.label}'), style: small),
              ],
            ),
          ],
        ),
        pw.Divider(color: primary, thickness: 1.2),
      ]),
      footer: (ctx) => pw.Row(children: [
        pw.Expanded(
            child: pw.Text(_t('${s.shopName} - ${c.number}'),
                style: const pw.TextStyle(
                    fontSize: 7, color: PdfColors.grey600))),
        pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      ]),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: box('Cliente', [
                kv('Nome', c.customerName),
                kv('Telefone', c.customerPhone),
                kv('CPF/CNPJ', c.customerDoc),
                if (c.customerEmail.isNotEmpty) kv('E-mail', c.customerEmail),
                kv('Atendimento', c.type.label),
              ]),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: box('Veículo', [
                kv('Placa', c.vehicle.plate),
                kv('Veículo', c.vehicle.title),
                kv('Cor', c.vehicle.color),
                kv('Chassi', c.vehicle.chassis),
                kv('Km', c.vehicle.km),
                if (c.vehicle.fipeValue > 0)
                  kv('FIPE', '${money(c.vehicle.fipeValue)}${c.vehicle.fipeCode.isEmpty ? '' : ' (${c.vehicle.fipeCode})'}'),
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        if (hasInsurer) ...[
          box('Seguradora / regulação', [
            pw.Row(children: [
              pw.Expanded(child: kv('Seguradora', c.insurerName)),
              pw.Expanded(child: kv('Sinistro', c.claimNumber)),
            ]),
            pw.Row(children: [
              pw.Expanded(child: kv('Apólice', c.policyNumber)),
              pw.Expanded(child: kv('Regulador', c.regulatorName)),
            ]),
            pw.Row(children: [
              pw.Expanded(child: kv('Data do sinistro', date(c.accidentDate))),
              pw.Expanded(
                  child: kv(
                      'Aprovação',
                      c.approvedAt == null
                          ? 'pendente'
                          : '${date(c.approvedAt)}${c.approvedBy.isEmpty ? '' : ' por ${c.approvedBy}'}')),
            ]),
          ]),
          pw.SizedBox(height: 8),
        ],
        if (c.description.trim().isNotEmpty) ...[
          box('Relato', [pw.Text(_t(c.description.trim()), style: normal)]),
          pw.SizedBox(height: 8),
        ],
        if (c.damages.isNotEmpty) ...[
          box('Avarias constatadas', [
            pw.Wrap(spacing: 10, runSpacing: 2, children: [
              for (final e in c.damages.entries)
                pw.Text(
                    _t('- ${regionById(e.key)?.label ?? e.key} (${severityLabels[e.value] ?? ''})'),
                    style: normal),
            ]),
          ]),
          pw.SizedBox(height: 8),
        ],
        pw.Text('Peças e serviços',
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold, color: primary)),
        pw.SizedBox(height: 4),
        if (items.isEmpty)
          pw.Text('Nenhum item lançado.', style: normal)
        else
          pw.TableHelper.fromTextArray(
            headers: [
              'Sigla',
              'Peça / serviço',
              'Origem',
              'Qtd',
              'M.O. (h)',
              'Pint. (h)',
              if (withPrices) 'Peça/serv.',
              if (withPrices) 'Total',
            ],
            data: [
              for (final it in items)
                () {
                  final v = itemValues(it, s);
                  final priced =
                      it.op == ItemOp.troca || it.op == ItemOp.servico;
                  return <String>[
                    opCode(it.op, it.laborHours, it.paintHours,
                        removeInstall: it.removeInstall),
                    _t(it.description +
                        (it.partNumber.isEmpty ? '' : '  (${it.partNumber})')),
                    _t(it.op == ItemOp.troca ? _originShort(it.origin) : ''),
                    priced ? num2(it.qty <= 0 ? 1 : it.qty) : '',
                    it.laborHours > 0 ? num2(it.laborHours) : '',
                    it.paintHours > 0 ? num2(it.paintHours) : '',
                    if (withPrices)
                      priced ? _t(money(v.parts + v.services)) : '',
                    if (withPrices) _t(money(v.total)),
                  ];
                }(),
            ],
            border: const pw.TableBorder(
              horizontalInside:
                  pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
            ),
            headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: primary),
            headerAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            oddRowDecoration: const pw.BoxDecoration(color: light),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignments: {
              for (var i = 3; i < (withPrices ? 8 : 6); i++)
                i: pw.Alignment.centerRight,
              0: pw.Alignment.center,
            },
            cellAlignments: {
              for (var i = 3; i < (withPrices ? 8 : 6); i++)
                i: pw.Alignment.centerRight,
              0: pw.Alignment.center,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(38),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FixedColumnWidth(50),
              3: const pw.FixedColumnWidth(24),
              4: const pw.FixedColumnWidth(44),
              5: const pw.FixedColumnWidth(44),
              if (withPrices) 6: const pw.FixedColumnWidth(62),
              if (withPrices) 7: const pw.FixedColumnWidth(66),
            },
          ),
        if (withPrices) ...[
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                        _t('Valor hora: ${[for (final lt in LaborType.values) '${lt.label} ${money(s.rateFor(lt))}'].join(' - ')} - Pintura ${money(s.paintRate)} + material ${money(s.paintMaterialRate)}'),
                        style: small),
                    pw.SizedBox(height: 4),
                    if (c.dueDate != null)
                      pw.Text(_t('Previsão de entrega: ${date(c.dueDate)}'), style: normal),
                    pw.Text(
                        _t('Validade do orçamento: ${s.budgetValidityDays} dias'),
                        style: normal),
                    if (items.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      legendBox,
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Container(
                width: 220,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: light,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(children: [
                  totalRow('Peças', money(totals.parts)),
                  totalRow('Mão de obra (${num2(totals.laborHours)} h)', money(totals.labor)),
                  totalRow('Pintura (${num2(totals.paintHours)} h)', money(totals.paintLabor)),
                  totalRow('Material de pintura', money(totals.paintMaterial)),
                  totalRow('Serviços', money(totals.services)),
                  if (totals.extra > 0) totalRow('Outros custos', money(totals.extra)),
                  if (totals.discount > 0)
                    totalRow('Desconto (${num2(c.discountPct)}%)', '- ${money(totals.discount)}'),
                  pw.Divider(thickness: 0.6),
                  totalRow('TOTAL', money(totals.total), strong: true),
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
        if (!withPrices && items.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          legendBox,
        ],
        if (images.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text('Fotos', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primary)),
          pw.SizedBox(height: 6),
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
                      pw.Container(
                        height: 120,
                        width: 170,
                        child: pw.Image(img, fit: pw.BoxFit.cover),
                      ),
                      pw.Text(cap, style: small, maxLines: 2),
                    ],
                  ),
                ),
            ],
          ),
        ],
        pw.SizedBox(height: 16),
        if (s.budgetFooter.trim().isNotEmpty)
          pw.Text(_t(s.budgetFooter.trim()), style: small),
        pw.SizedBox(height: 36),
        pw.Row(children: [
          pw.Expanded(child: _signature(_t(s.shopName))),
          pw.SizedBox(width: 40),
          pw.Expanded(
              child: _signature(_t(c.customerName.isEmpty
                  ? 'Cliente'
                  : c.customerName))),
        ]),
      ],
    ),
  );
  return doc.save();
}

String _originShort(PartOrigin o) {
  switch (o) {
    case PartOrigin.nenhuma:
      return '';
    case PartOrigin.original:
      return 'Original';
    case PartOrigin.genuina:
      return 'Genuína';
    case PartOrigin.paralela:
      return 'Paralela';
    case PartOrigin.usada:
      return 'Usada';
  }
}

pw.Widget _signature(String name) => pw.Column(children: [
      pw.Divider(thickness: 0.6),
      pw.Text(name, style: const pw.TextStyle(fontSize: 8)),
    ]);

String _fileName(Claim c, bool prices) =>
    '${prices ? 'orcamento' : 'vistoria'}-${c.number}${c.vehicle.plate.isEmpty ? '' : '-${c.vehicle.plate}'}.pdf'
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

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
  final name = _fileName(c, withPrices);
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
