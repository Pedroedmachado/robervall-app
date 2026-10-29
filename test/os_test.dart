import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/finance.dart';
import 'package:funilar/format.dart';
import 'package:funilar/models.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/store.dart';

void main() {
  test('insumos saem do estoque e entram no custo real da O.S.', () async {
    final store = await AppStore.open(assumeLicense: License.full(), 
        dir: await Directory.systemTemp.createTemp('funilar_os'));
    final lixa = StockItem(
        kind: StockKind.material, name: 'Lixa P320', qty: 50, unit: 'folha', cost: 2);
    final verniz = StockItem(
        kind: StockKind.material, name: 'Verniz HS', qty: 4, unit: 'quarto', cost: 89);
    final farol = StockItem(name: 'Farol esquerdo', qty: 1, cost: 250, price: 390);
    for (final s in [lixa, verniz, farol]) {
      store.upsertStock(s);
    }
    final pintor = Contact(
        kind: ContactKind.funcionario, name: 'Luan', payType: PayType.porPeca, rate: 100);
    store.upsertContact(pintor);

    final porta = BudgetItem(
        description: 'Porta', op: ItemOp.reparo, perPiece: true, piecePrice: 600, doPaint: true);
    final c = store.newClaim()
      ..items = [
        porta,
        BudgetItem(description: 'Farol esquerdo', op: ItemOp.troca, price: 390, stockId: farol.id),
      ]
      ..crew = [CrewMember(role: OutsourcedService.pintura, contactId: pintor.id)];
    store.touch(c);

    final u = store.issueSupply(c, lixa, 10, itemId: porta.id);
    store.issueSupply(c, verniz, 1);
    expect(lixa.qty, 40);
    expect(verniz.qty, 3);
    expect(suppliesByItem(c)[porta.id], 20);

    store.entries.add(FinanceEntry(amount: 50, claimId: c.id, description: 'Guincho'));
    final j = jobCost(c, store.settings,
        entries: store.entries,
        contactById: store.contactById,
        stockById: store.stockById);
    expect(j.approved, 990);
    expect(j.crew, 100); // 1 peça pintada × 100
    expect(j.supplies, 109); // 10 × 2 + 89
    expect(j.stockParts, 250);
    expect(j.otherExpenses, 50);
    expect(j.total, 509);
    expect(j.profit, 481);
    expect(j.marginPct, closeTo(48.59, 0.01));

    store.returnSupply(c, u);
    expect(lixa.qty, 50);
    expect(c.supplies.length, 1);

    // ida e volta no JSON
    c.preDamages['capo'] = 1;
    c.reception
      ..fuel = 2
      ..items.addAll({'Estepe', 'Macaco'})
      ..at = DateTime(2026, 10, 29, 8, 30);
    c.vehicle.km = '85000';
    porta.done = true;
    final back = Claim.fromJson(c.toJson());
    expect(back.preDamages, {'capo': 1});
    expect(back.reception.fuelLabel, '1/2');
    expect(back.reception.items, {'Estepe', 'Macaco'});
    expect(back.supplies.single.name, 'Verniz HS');
    expect(back.items.first.done, isTrue);
    expect(receptionLines(back).first,
        'Entrada: 29/10/2026 08:30   Combustível: 1/2   Km: 85000');
    expect(receptionLines(back)[1], 'No veículo: Estepe, Macaco');
  });

  test('endereço da peça e modo produção esconde valores', () async {
    final s = StockItem(corridor: '1', shelf: 'B5', slot: '3');
    expect(s.address, 'Corredor 1 · Prateleira B5 · Nicho 3');
    final back = StockItem.fromJson(
        StockItem(kind: StockKind.cliente, claimId: 'x', shelf: 'A').toJson());
    expect(back.kind, StockKind.cliente);
    expect(back.claimId, 'x');
    expect(back.address, 'Prateleira A');

    final store = await AppStore.open(assumeLicense: License.full(), 
        dir: await Directory.systemTemp.createTemp('funilar_modo'));
    expect(money(10), 'R\$ 10,00');
    expect(store.stock, isEmpty);
    expect(money(10), 'R\$ 10,00');
  });
}
