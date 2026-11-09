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
    expect(lines[0].unit, 'un');
    expect(lines[1].unit, 'litro');
    expect(lines[0].qty, 4);
    expect(lines[0].unitCost, 89);
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
