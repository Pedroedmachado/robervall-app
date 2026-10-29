import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/models.dart';
import 'package:funilar/pdf_report.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/store.dart';
import 'package:funilar/ui/stock_page.dart';

void main() {
  test('acha a peça do estoque pelo nome ou código, sem trocar o lado', () {
    final farolE = StockItem(name: 'Farol esquerdo Gol G5', qty: 2);
    final farolD = StockItem(name: 'Farol direito', qty: 1);
    final tinta = StockItem(name: 'Farol esquerdo', kind: StockKind.material);
    final porCodigo = StockItem(name: 'Peça X', partNumber: '5U0-941-005', qty: 1);
    final stock = [farolE, farolD, tinta, porCodigo];

    final it = BudgetItem(description: 'Farol esq', op: ItemOp.troca);
    expect(stockFor(stock, it), [farolE]);
    expect(stockFor(stock, BudgetItem(description: 'Farol direito', op: ItemOp.troca)),
        [farolD]);
    // reparo não procura estoque
    expect(stockFor(stock, BudgetItem(description: 'Farol esquerdo', op: ItemOp.reparo)), isEmpty);
    expect(
        stockFor(stock,
            BudgetItem(description: 'Qualquer', partNumber: '5U0941005', op: ItemOp.troca)),
        [porCodigo]);
    // sem saldo some, a não ser que já esteja em uso no item
    farolE.qty = 0;
    expect(stockFor(stock, it), isEmpty);
    it.stockId = farolE.id;
    expect(stockFor(stock, it), [farolE]);

    final back = StockItem.fromJson(farolD.toJson());
    expect(back.name, 'Farol direito');
    expect(back.kind, StockKind.peca);
  });

  test('baixa no estoque quando aprova e devolve quando reabre', () async {
    final store = await AppStore.open(assumeLicense: License.full(), 
        dir: await Directory.systemTemp.createTemp('funilar_estoque'));
    final farol = StockItem(name: 'Farol esquerdo', qty: 3, cost: 200, price: 320);
    store.upsertStock(farol);
    final it = BudgetItem(
        description: 'Farol esquerdo', op: ItemOp.troca, stockId: farol.id, qty: 2);
    final c = store.newClaim()..items = [it];
    store.touch(c);
    expect(farol.qty, 3); // orçamento aberto: ainda não sai

    store.setStatus(c, ClaimStatus.aprovado);
    expect(farol.qty, 1);
    store.touch(c); // não tira de novo
    expect(farol.qty, 1);

    it.qty = 1; // mudou a quantidade
    store.touch(c);
    expect(farol.qty, 2);

    store.setStatus(c, ClaimStatus.orcamento);
    expect(farol.qty, 3);

    store.setStatus(c, ClaimStatus.entregue);
    expect(farol.qty, 2);
    c.items.remove(it); // tirou o item: volta
    store.touch(c);
    expect(farol.qty, 3);

    c.items.add(it);
    store.touch(c);
    expect(farol.qty, 2);
    expect(Claim.fromJson(c.toJson()).stockTaken[it.id]?.qty, 1);
    expect(store.duplicate(c).stockTaken, isEmpty);
    await store.deleteClaim(c);
    expect(farol.qty, 3);
  });

  test('nome do PDF é modelo e placa', () {
    final c = Claim(number: 'FN-0007')
      ..vehicle.model = 'Gol 1.0'
      ..vehicle.plate = 'abc-1d23';
    expect(pdfFileName(c), 'Gol 1.0 ABC-1D23.pdf');
    expect(pdfFileName(Claim(number: 'FN-0008')), 'FN-0008.pdf');
    c.vehicle.model = 'Onix 1.0/Turbo';
    expect(pdfFileName(c), 'Onix 1.0-Turbo ABC-1D23.pdf');
  });

  test('busca no Mercado Livre usa peça, modelo e ano', () {
    final v = Vehicle(model: 'Gol 1.0', year: '2019');
    final u = marketSearchUri(
        BudgetItem(description: 'Farol esquerdo', op: ItemOp.troca), v);
    expect(u.toString(),
        'https://lista.mercadolivre.com.br/farol-esquerdo-gol-1-0-2019');
  });
}
