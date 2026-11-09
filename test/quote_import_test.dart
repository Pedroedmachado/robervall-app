import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/calc.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/main.dart';
import 'package:funilar/models.dart';
import 'package:funilar/pdf_words.dart';
import 'package:funilar/quote_import.dart';
import 'package:funilar/store.dart';
import 'package:funilar/ui/quote_import_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Palavras (com posição) tiradas de um orçamento real do Cilia, com nomes,
/// documentos, placa e chassi trocados por dados de exemplo.
List<PdfWord> ciliaWords() {
  final raw = jsonDecode(File('test/fixtures/cilia_words.json').readAsStringSync()) as List;
  return raw.map((e) => PdfWord.fromJson(Map<String, dynamic>.from(e as Map))).toList();
}

List<PdfWord> portoWords() {
  final raw =
      jsonDecode(File('test/fixtures/porto_soma_words.json').readAsStringSync()) as List;
  return raw.map((e) => PdfWord.fromJson(Map<String, dynamic>.from(e as Map))).toList();
}

void main() {
  test('orçamento detalhado da Porto (SOMA): cabeçalho, itens e total', () {
    final q = parseInsurerQuote(portoWords());
    final c = q.claim;
    expect(q.system, 'Porto (SOMA)');
    expect(c.type, ClaimType.seguradora);
    expect(c.claimNumber, '1234567890123');
    expect(c.policyNumber, '1111111');
    expect(c.customerName, 'MARIA TESTE DE EXEMPLO SILVA');
    expect(c.customerPhone, '(11) 90000-0000');
    expect(c.insurerName, 'PORTO SEGURO');
    expect(c.regulatorName, 'REGULACAO NEXO 1');
    expect(c.vehicle.brand, 'RENAULT');
    expect(c.vehicle.model, 'SANDERO STEPWAY 1.6 8V HI');
    expect(c.vehicle.plate, 'ABC1D23');
    expect(c.vehicle.chassis, '93Y5SRD6GHJ000000');
    expect(c.vehicle.color, 'CINZA');
    expect(c.vehicle.year, '2016/2017');
    expect(c.laborRate, 62);
    expect(c.paintRate, 62);
    expect(q.partsDiscountPct, 14);
    expect(c.deductible, 6875);
    expect(c.notes, contains('10000001'));
    expect(c.notes, contains('LIBERADO'));

    final troca = c.items.where((e) => e.op == ItemOp.troca).toList();
    expect(troca.length, 9);
    final tampa = troca.firstWhere((e) => e.partNumber == '901008080R');
    expect(tampa.description, 'TAMPA TRAS.S/FURO AEROFOLIO');
    expect(tampa.price, 2345.10);
    expect(tampa.discountPct, 14);
    expect(tampa.laborHours, 2);
    expect(tampa.paintHours, 4);
    expect(tampa.note, contains('EQ.E0,E1,E2,E3'));
    expect(troca.firstWhere((e) => e.partNumber == '265604000R').description,
        'REFLETOR P/CHOQUE TRA');
    expect(troca.firstWhere((e) => e.partNumber == '265509406R').description,
        'LANTERNA TRAS.LD C/M.NEG');
    // mão de obra extra da tampa (amortecedor, fechadura…)
    final ri = c.items.where((e) => e.op == ItemOp.reparo && e.removeInstall).toList();
    expect(ri.map((e) => e.description), contains('amortecedor da tampa'));
    expect(ri.length, 4 + 3);
    // recuperar + restaurar emblemas
    expect(c.items.where((e) => e.op == ItemOp.reparo && !e.removeInstall).length, 3);
    expect(c.items.where((e) => e.op == ItemOp.servico).length, 3);

    expect(q.pdfTotal, 7292);
    expect(computeTotals(c, Settings()).total, closeTo(7292, 0.05));
  });

  test('números no formato brasileiro', () {
    expect(parseBrNumber('R\$ 1.500,05'), 1500.05);
    expect(parseBrNumber('26,00%'), 26);
    expect(parseBrNumber('R\$ 69,77/h'), 69.77);
    expect(parseBrNumber('128394.0'), 128394);
    expect(parseBrNumber('-'), isNull);
  });

  test('orçamento do Cilia: cabeçalho, itens e total', () {
    final q = parseInsurerQuote(ciliaWords());
    final c = q.claim;
    expect(q.system, 'Cilia');
    expect(q.recognized, isTrue);

    final v = c.vehicle;
    expect(v.plate, 'ABC-1D23');
    expect(v.brand, 'CHEVROLET');
    expect(v.model, 'ONIX (2017 A 2019) JOY 1.0 8V FLEX');
    expect(v.year, '2019');
    expect(v.color, 'PRATA');
    expect(v.chassis, '9BGKL48U0KB000000');
    expect(v.km, '128394');
    expect(v.fuel, '0/8');
    expect(v.fipeValue, 50210);
    expect(v.fipeCode, '0044733');

    expect(c.insurerName, 'Tokio Marine');
    expect(c.claimNumber, '123456789');
    expect(c.type, ClaimType.terceiro);
    expect(c.customerName, 'MARIA TESTE EXEMPLO');
    expect(c.customerDoc, '000.000.000-00');
    expect(c.customerPhone, '');
    expect(c.regulatorName, 'Fulano de Tal (SM Reguladora)');
    expect(c.laborRate, 69.77);
    expect(c.paintRate, 69.77);
    expect(q.partsDiscountPct, 26);
    expect(c.notes, contains('1000001.2'));
    expect(c.notes, contains('Reparo Autorizado'));

    expect(c.items.map((e) => e.description).toList(), [
      'ESPELHO RETROVISOR ESQ',
      'FAROL ESQUERDO',
      'PARABARRO DIANT ESQ',
      'PARACHOQUE DIANTEIRO',
      'PORTA DIANTEIRA ESQ',
      'PARALAMA DIANT ESQ',
    ]);
    final espelho = c.items[0];
    expect(espelho.op, ItemOp.reparo);
    expect(espelho.removeInstall, isTrue);
    expect(espelho.alsoRepair, isFalse);
    expect(espelho.laborHours, 0.5);
    expect(espelho.note, '(AJUSTE MANUAL)');
    expect(c.items[2].note, '(CONSULTAR VIN 2017 A 2019)');
    final para = c.items[3];
    expect(para.removeInstall && para.alsoRepair, isTrue);
    expect(para.laborHours, 3);
    expect(para.paintHours, 3);
    final paralama = c.items[5];
    expect(paralama.removeInstall, isFalse);
    expect(paralama.laborHours, 2);
    expect(paralama.paintHours, 3);

    // com os valores da hora do PDF o total bate com o do Cilia
    expect(q.pdfTotal, 1500.06);
    final t = computeTotals(c, Settings());
    expect(t.total, closeTo(1500.06, 0.02));
    expect(t.paintMaterial, 0);
  });

  test('valores da hora próprios do orçamento', () {
    final s = Settings();
    final c = Claim(items: [BudgetItem(op: ItemOp.reparo, laborHours: 2, paintHours: 1)]);
    expect(computeTotals(c, s).total, 2 * 90 + 1 * (90 + 70));
    c.laborRate = 50;
    c.paintRate = 100;
    expect(computeTotals(c, s).total, 2 * 50 + 1 * 100);
    final back = Claim.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
    expect(back.laborRate, 50);
    expect(back.paintRate, 100);
    expect(s.forClaim(Claim()), same(s));
  });

  test('PDF de verdade: extrai o texto e lê troca com preço', () async {
    final doc = pw.Document();
    pw.Widget at(double x, double y, String t) =>
        pw.Positioned(left: x, top: y, child: pw.Text(t, style: const pw.TextStyle(fontSize: 7)));
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(children: [
        at(100, 14, 'XYZ - FIAT - ARGO DRIVE 1.0 2021'),
        at(86, 46, 'Placa'),
        at(170, 46, 'Cor'),
        at(86, 56, 'BRA2E19'),
        at(170, 56, 'BRANCO'),
        at(86, 75, 'Seguradora'),
        at(212, 75, 'Sinistro'),
        at(86, 85, 'Porto Seguro'),
        at(212, 85, '555'),
        at(86, 105, 'Segurado'),
        at(86, 115, 'JOAO EXEMPLO'),
        at(338, 135, 'Mão de obra'),
        at(506, 135, 'Pintura'),
        at(338, 145, 'R\$ 80,00/h'),
        at(506, 145, 'R\$ 100,00/h'),
        at(15, 200, 'OPERAÇÕES'),
        at(145, 200, 'QTD.'),
        at(171, 200, 'CÓDIGO'),
        at(210, 200, 'TIPO'),
        at(236, 200, 'TÍTULO'),
        at(356, 200, 'FORNECIMENTO'),
        at(420, 200, 'PREÇO'),
        at(475, 200, 'DESCONTO'),
        at(525, 200, 'PREÇO LÍQUIDO'),
        at(18, 220, 'T 1,00 P 2,00'),
        at(145, 220, '1'),
        at(171, 220, '52080055'),
        at(210, 220, 'PG'),
        at(236, 220, 'PARACHOQUE DIANT'),
        at(356, 220, 'Oficina'),
        at(420, 220, 'R\$ 1.000,00'),
        at(475, 220, '26,00%'),
        at(525, 220, 'R\$ 740,00'),
        at(18, 240, 'R 1,50'),
        at(145, 240, '1'),
        at(236, 240, 'CAPO'),
        at(356, 240, 'Oficina'),
        at(32, 260, 'Troca / R&I'),
        at(7, 400, 'Relatório gerado pelo Sistema Cilia'),
      ]),
    ));
    final bytes = await doc.save();
    final words = extractPdfWords(bytes);
    expect(words, isNotEmpty);
    final q = parseInsurerQuote(words);
    final c = q.claim;
    expect(q.system, 'Cilia');
    expect(c.vehicle.plate, 'BRA2E19');
    expect(c.vehicle.brand, 'FIAT');
    expect(c.vehicle.year, '2021');
    expect(c.insurerName, 'Porto Seguro');
    expect(c.type, ClaimType.seguradora);
    expect(c.customerName, 'JOAO EXEMPLO');
    expect(c.laborRate, 80);
    expect(c.paintRate, 100);
    expect(c.items.length, 2);
    final t = c.items.first;
    expect(t.op, ItemOp.troca);
    expect(t.description, 'PARACHOQUE DIANT');
    expect(t.partNumber, '52080055');
    expect(t.origin, PartOrigin.genuina);
    expect(t.price, 1000);
    expect(t.discountPct, closeTo(26, 0.01));
    expect(t.laborHours, 1);
    expect(t.paintHours, 2);
    expect(c.items[1].op, ItemOp.reparo);
    expect(c.items[1].laborHours, 1.5);
  });

  testWidgets('conferir e criar o orçamento importado', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = (await t.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('funilar_imp');
      return AppStore.open(assumeLicense: License.full(), dir: dir);
    }))!;
    await t.pumpWidget(FunilarApp(store: store));
    await t.pumpAndSettle();
    final before = store.claims.length;

    final q = parseInsurerQuote(ciliaWords());
    final ctx = t.element(find.byType(Scaffold).first);
    reviewImportedQuote(ctx, q);
    await t.pumpAndSettle();
    expect(find.text('Conferir orçamento importado'), findsOneWidget);
    await t.scrollUntilVisible(find.text('✓ Bate com o PDF.'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('✓ Bate com o PDF.'), findsOneWidget);

    await t.tap(find.text('Criar orçamento').first);
    await t.pumpAndSettle();
    expect(store.claims.length, before + 1);
    final c = store.claims.first;
    expect(c.number, isNotEmpty);
    expect(c.items.length, 6);
    expect(c.laborRate, 69.77);
    expect(c.sourceSystem, 'Cilia');
    expect(c.vehicle.plate, 'ABC-1D23');
    expect(c.timeline.any((e) => e.text.contains('importado do PDF')), isTrue);
    expect(computeTotals(c, store.settings).total, closeTo(1500.06, 0.02));

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 7));
  });
}
