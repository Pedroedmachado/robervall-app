import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/main.dart';
import 'package:funilar/models.dart';
import 'package:funilar/receipt_parser.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/stock_entry.dart';
import 'package:funilar/store.dart';
import 'package:funilar/ui/stock_entry_ui.dart';

const _nfe = '''<?xml version="1.0" encoding="UTF-8"?>
<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00"><NFe><infNFe Id="NFe3526" versao="4.00">
<ide><cUF>35</cUF><nNF>48213</nNF><dhEmi>2026-11-03T10:15:00-03:00</dhEmi></ide>
<emit><CNPJ>00000000000100</CNPJ><xNome>TINTAS EXEMPLO LTDA</xNome><xFant>Tintas Exemplo</xFant></emit>
<det nItem="1"><prod><cProd>VZ-1300</cProd><xProd>VERNIZ HS 2X1 900ML</xProd><uCom>UN</uCom><qCom>4.0000</qCom><vUnCom>89.0000000000</vUnCom><vProd>356.00</vProd></prod></det>
<det nItem="2"><prod><cProd>52080055</cProd><xProd>PARA-CHOQUE DIANT &amp; GRADE</xProd><uCom>PC</uCom><qCom>1.0000</qCom><vUnCom>500.00</vUnCom><vProd>500.00</vProd><vDesc>50.00</vDesc></prod></det>
<det nItem="3"><prod><cProd>LX-320</cProd><xProd>LIXA P320</xProd><uCom>FL</uCom><qCom>50.0000</qCom><vUnCom>1.2000</vUnCom><vProd>60.00</vProd></prod></det>
<total><ICMSTot><vProd>916.00</vProd><vNF>866.00</vNF></ICMSTot></total>
<pag><detPag><tPag>17</tPag><vPag>866.00</vPag></detPag></pag>
</infNFe></NFe></nfeProc>''';

void main() {
  test('lê o XML da NF-e', () {
    final d = parseNfeXml(_nfe)!;
    expect(d.supplier, 'Tintas Exemplo');
    expect(d.date, DateTime(2026, 11, 3));
    expect(d.docNumber, 'NF-e 48213');
    expect(d.total, 866);
    expect(d.payment, 'Pix');
    expect(d.items.length, 3);
    expect(d.items[0].code, 'VZ-1300');
    expect(d.items[0].qty, 4);
    expect(d.items[0].unitPrice, 89);
    expect(d.items[1].description, 'PARA-CHOQUE DIANT & GRADE');
    expect(d.items[1].unitPrice, 450); // com o desconto do item
    expect(parseNfeXml('<html></html>'), isNull);
  });

  test('entrada soma no que existe e cria o que falta', () {
    final verniz = StockItem(
        kind: StockKind.material,
        name: 'Verniz HS 2x1',
        mfrCode: 'VZ-1300',
        unit: 'ml',
        qty: 900,
        packName: 'lata',
        packSize: 900,
        packCost: 80)
      ..syncPackCost();
    final lixa = StockItem(kind: StockKind.material, name: 'Lixa P320', unit: 'folha', qty: 10, cost: 1);
    final stock = [verniz, lixa];
    final lines = planStockEntry(parseNfeXml(_nfe)!, stock);
    expect(lines.length, 3);
    expect(lines[0].match, same(verniz)); // mesmo código
    expect(lines[1].match, isNull);
    expect(lines[1].kind, StockKind.peca);
    expect(lines[1].unit, 'un');
    expect(lines[2].match, same(lixa)); // mesmo nome
    expect(lines[2].unit, 'folha');

    final created = applyStockEntry(lines, docLabel: 'NF-e 48213');
    expect(verniz.qty, 900 + 4 * 900); // 4 latas de 900 ml
    expect(verniz.packCost, 89);
    expect(verniz.cost, closeTo(89 / 900, 1e-9));
    expect(lixa.qty, 60);
    expect(lixa.cost, 1.2);
    expect(lixa.notes, contains('NF-e 48213'));
    expect(created.length, 1);
    expect(created.first.name, 'PARA-CHOQUE DIANT & GRADE');
    expect(created.first.partNumber, '52080055');
    expect(created.first.cost, 450);
  });

  test('nota lida pela foto vira entrada (unidades e tipo)', () {
    final d = parseReceipt(const [
      'ART COLOR TINTAS',
      '22/09/2026-17:19',
      'QTDE UNID   PRC UNIT   TOTAL',
      'VERNIZ A.SOLIDOS HS-2X1 13000 C/CAT.SKY',
      '4,00 QUART   89,00   356,00',
      'ACELERADOR SECAGEM RRA- 1LT SIKKENS',
      '1,00 LITRO   53,90   53,90',
      'TOTAL :   409,90',
    ]);
    final lines = planStockEntry(d, []);
    expect(lines.length, 2);
    expect(lines.every((l) => l.kind == StockKind.material), isTrue);
    expect(lines[0].unit, 'ml');
    expect(lines[0].packSize, 900);
    expect(lines[0].packName, 'lata');
    expect(lines[1].unit, 'litro');
    expect(lines[0].qty, 4);
    expect(lines[0].unitCost, 89);
  });

  // Notas reais da Art Color (foto, como o leitor do celular devolve).
  const nota1 = [
    'ART COLOR TINTAS',
    'AV DO CURSINO, 1916',
    'FONE: 001150738518',
    '-----------------------------------------',
    'RESERVA A PRAZO 0823147',
    '23/10/2026-16:01 VEND: 00005-ROBSON SIL',
    '000000838 - ABEL STOPCAR',
    'QTDE UNID   PRC UNIT   TOTAL',
    'PRATA POLARIS-GM-06 900ML LAZZUDUR',
    '4,00 QUART   47,50   190,00',
    'VERNIZ A.SOLIDOS HS-2X1 13000 C/CAT.SKY',
    '3,00 QUART   89,00   267,00',
    'FITA CREPE VERDE AUTOMOT.18X40MTS ADERE',
    '5,00 UND   5,95   29,75',
    '-----------------------------------------',
    'TOTAL :   486,75',
    'A vista',
    'DOCUMENTO SEM VALOR FISCAL !',
  ];
  const nota2 = [
    'ART COLOR TINTAS',
    'AV DO CURSINO, 1916',
    'RESERVA 0823971',
    '30/10/2026-13:50 VEND: 00010-ALISSON SA',
    'QTDE UNID   PRC UNIT   TOTAL',
    'PRETO ECLYPSE MET.TOYOTA-09(209) SKYLACK',
    '2,00 QUART   49,95   99,90',
    'PRATA BARI MET.FIAT-02 900ML SKY',
    '2,00 QUART   41,90   83,80',
    'VERNIZ A.SOLIDOS HS-2X1 13000 C/CAT.SKY',
    '3,00 QUART   89,00   267,00',
    'THINNER PU /POLIES.TH700 900ML SKY',
    '2,00 LITRO   41,00   82,00',
    'MASSA POLIESTER M3500-750GR SHERWIN-WILL',
    '4,00 750GR   33,90   135,60',
    'KIT PRIMER P.U 8200 CINZA-LAZZUDUR',
    '3,00 KIT   57,50   172,50',
    'FITA CREPE VERDE AUTOMOT.18X40MTS ADERE',
    '6,00 UND   5,95   35,70',
    'SOLUCAO DESENGRAXANTE 900ML FARBEN',
    '1,00 900ML   19,50   19,50',
    'MASSA POLIR SUPER POLIDOR 1KG.AUTOAMERIC',
    '1,00 1KG   36,90   36,90',
    'LIXA DAGUA 1200 NORTON-AMARELA',
    '5,00 FL   6,95   34,75',
    '-----------------------------------------',
    'TOTAL :   967,65',
    'A vista',
    'TOTAL DE DEBITOS : R\$ 40.126,15',
    'DOCUMENTO SEM VALOR FISCAL !',
  ];

  test('nota real 1 (Art Color, 3 itens) entra no estoque', () {
    final d = parseReceipt(nota1);
    expect(d.supplier, 'Art Color Tintas');
    expect(d.date, DateTime(2026, 10, 23));
    expect(d.total, closeTo(486.75, 0.001));
    expect(d.items.length, 3);
    expect(d.itemsSum, closeTo(486.75, 0.001));
    final lines = planStockEntry(d, []);
    expect(lines.every((l) => l.kind == StockKind.material), isTrue);
    expect(lines[0].packSize, 900); // lata de 900 ml (QUART)
    expect(lines[2].unit, 'un'); // fita: UND
    final created = applyStockEntry(lines);
    final prata = created[0];
    expect(prata.qty, 3600); // 4 latas × 900 ml
    expect(prata.unit, 'ml');
    expect(prata.packCost, 47.5);
    expect(prata.stockValue, closeTo(190, 0.01));
    expect(created[2].qty, 5);
    expect(created[2].cost, 5.95);
  });

  test('nota real 2 (Art Color, 10 itens): embalagens e total', () {
    final d = parseReceipt(nota2);
    expect(d.date, DateTime(2026, 10, 30));
    expect(d.total, closeTo(967.65, 0.001)); // não pega o "total de débitos"
    expect(d.items.length, 10);
    expect(d.itemsSum, closeTo(967.65, 0.001));
    final lines = planStockEntry(d, []);
    expect(lines.every((l) => l.kind == StockKind.material), isTrue);
    final created = applyStockEntry(lines);
    final value = created.fold(0.0, (a, s) => a + s.stockValue);
    expect(value, closeTo(967.65, 0.05));
    StockItem byName(String n) => created.firstWhere((s) => s.name.toUpperCase().startsWith(n));
    expect(byName('THINNER').unit, 'litro');
    expect(byName('THINNER').qty, 2);
    final massa = byName('MASSA POLIESTER');
    expect(massa.unit, 'g');
    expect(massa.packSize, 750);
    expect(massa.qty, 3000);
    final polir = byName('MASSA POLIR');
    expect(polir.unit, 'g');
    expect(polir.packSize, 1000);
    final desengr = byName('SOLUCAO');
    expect(desengr.unit, 'ml');
    expect(desengr.qty, 900);
    final lixa = byName('LIXA');
    expect(lixa.unit, 'folha');
    expect(lixa.qty, 5);
    expect(byName('KIT PRIMER').unit, 'un');
  });

  test('a mesma tinta comprada de novo soma na lata que já existe', () {
    final d1 = parseReceipt(nota1);
    final stock = applyStockEntry(planStockEntry(d1, []));
    final d2 = parseReceipt(nota2);
    final lines = planStockEntry(d2, stock);
    final verniz = lines.firstWhere((l) => l.name.toUpperCase().startsWith('VERNIZ'));
    expect(verniz.match, isNotNull);
    final fita = lines.firstWhere((l) => l.name.toUpperCase().startsWith('FITA'));
    expect(fita.match, isNotNull);
    applyStockEntry(lines);
    final v = stock.firstWhere((s) => s.name.toUpperCase().startsWith('VERNIZ'));
    expect(v.qty, 6 * 900); // 3 + 3 latas
    expect(stock.firstWhere((s) => s.name.toUpperCase().startsWith('FITA')).qty, 11);
  });

  testWidgets('conferir e dar entrada (com gasto no Financeiro)', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = (await t.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('funilar_ent');
      return AppStore.open(assumeLicense: License.full(), dir: dir);
    }))!;
    store.upsertStock(StockItem(kind: StockKind.material, name: 'Lixa P320', unit: 'folha', qty: 10, cost: 1));
    await t.pumpWidget(FunilarApp(store: store));
    await t.pumpAndSettle();
    final entriesBefore = store.entries.length;

    final ctx = t.element(find.byType(Scaffold).first);
    reviewStockEntry(ctx, parseNfeXml(_nfe)!);
    await t.pumpAndSettle();
    expect(find.text('Entrada pela nota'), findsOneWidget);
    expect(find.textContaining('Soma em "Lixa P320"', skipOffstage: false), findsOneWidget);

    await t.tap(find.text('Dar entrada'));
    await t.pumpAndSettle();
    expect(store.stock.length, 3);
    expect(store.stock.firstWhere((s) => s.name == 'Lixa P320').qty, 60);
    expect(store.entries.length, entriesBefore + 1);
    final e = store.entries.firstWhere((e) => e.invoiceNumber == 'NF-e 48213');
    expect(e.amount, 866);
    expect(e.isIncome, isFalse);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 7));
  });
}
