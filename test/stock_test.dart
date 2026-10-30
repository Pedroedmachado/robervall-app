import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/format.dart';
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

  test('embalagem: custo por unidade, rótulos e leitura do nome', () {
    final t = StockItem(
        kind: StockKind.material,
        name: 'Thinner 900ml',
        unit: 'ml',
        packName: 'lata',
        packSize: 900,
        packCost: 41,
        qty: 450);
    t.syncPackCost();
    expect(t.cost, closeTo(0.04556, 1e-4));
    expect(t.qtyLabel, '450 ml (0,5 lata)');
    expect(unitMoney(t.cost), 'R\$ 0,0456');
    expect(unitMoney(2.5), 'R\$ 2,50');
    final back = StockItem.fromJson(t.toJson());
    expect(back.packSize, 900);
    expect(back.packCost, 41);
    expect(StockItem(qty: 3).qtyLabel, '3 un');
    expect(packFromName('Thinner TH700 900Ml'), (900.0, 'ml'));
    expect(packFromName('Verniz HS 3,6 L'), (3.6, 'litro'));
    expect(packFromName('Lixa P320'), isNull);
    expect(StockItem(packName: 'galão', packSize: 3600, qty: 7200, unit: 'ml').qtyLabel,
        '7200 ml (2 galões)');
  });

  test('lixa: folha em quartos e disco', () {
    expect(qtyText(0.25, 'folha'), '1/4 de folha');
    expect(qtyText(0.5, 'folha'), '1/2 folha');
    expect(qtyText(1, 'folha'), '1 folha');
    expect(qtyText(2.75, 'folha'), '2 e 3/4 folhas');
    expect(qtyText(0.3, 'folha'), '0,3 folha');
    expect(qtyText(3, 'disco'), '3 discos');
    expect(StockItem(kind: StockKind.material, name: 'Lixa P400', unit: 'folha').isSandpaper, isTrue);
    expect(StockItem(kind: StockKind.material, name: 'Thinner', unit: 'ml').isSandpaper, isFalse);
    expect(StockItem(kind: StockKind.material, name: 'Disco 6 pol', unit: 'disco', qty: 1).qtyLabel, '1 disco');
  });

  test('peça: aplicação veicular, código OEM e cadastro repetido', () {
    final gol = StockItem(
        name: 'Farol esquerdo',
        partNumber: '5U0-941.005',
        sku: 'P-0007',
        applications: [VehicleFit(make: 'VW', model: 'Gol', yearFrom: 2013, yearTo: 2016, engine: '1.0')]);
    final stock = [gol];
    // mesmo OEM escrito diferente
    expect(findDuplicates(stock, StockItem(name: 'Farol', partNumber: '5u0941005')).single.$2,
        'mesmo código OEM');
    // mesmo nome e carro com anos que se cruzam
    expect(findDuplicates(stock, StockItem(name: 'Farol esq', applications: [
      VehicleFit(make: 'Volkswagen', model: 'gol', yearFrom: 2015, yearTo: 2018)
    ])).single.$2, 'mesmo nome e mesmo carro');
    // mesmo nome, carro diferente: não é repetido
    expect(findDuplicates(stock, StockItem(name: 'Farol esquerdo', applications: [
      VehicleFit(make: 'Fiat', model: 'Uno', yearFrom: 2010, yearTo: 2014)
    ])), isEmpty);
    // lado diferente: não é repetido
    expect(findDuplicates(stock, StockItem(name: 'Farol direito')), isEmpty);
    // insumo não entra na conferência
    expect(findDuplicates(stock, StockItem(kind: StockKind.material, name: 'Farol esquerdo')), isEmpty);

    expect(nextSku(stock), 'P-0008');
    expect(nextSku([]), 'P-0001');
    expect(canonicalMake('vw'), 'Volkswagen');
    expect(canonicalMake('GM'), 'Chevrolet');
    expect(gol.applications.single.label, 'VW Gol 1.0 2013–2016');

    // serve no carro do sinistro?
    expect(fitsVehicle(gol, Vehicle(brand: 'Volkswagen', model: 'Gol 1.0 MPI', year: '2014')), isTrue);
    expect(fitsVehicle(gol, Vehicle(brand: 'Volkswagen', model: 'Gol', year: '2019')), isFalse);
    expect(fitsVehicle(gol, Vehicle(brand: 'Fiat', model: 'Uno', year: '2014')), isFalse);
    expect(fitsVehicle(StockItem(name: 'x'), Vehicle(model: 'Uno')), isTrue);
    final item = BudgetItem(description: 'Farol esquerdo', op: ItemOp.troca);
    gol.qty = 1;
    expect(stockFor(stock, item, Vehicle(brand: 'Fiat', model: 'Uno', year: '2014')), isEmpty);
    expect(stockFor(stock, item, Vehicle(brand: 'VW', model: 'Gol', year: '2014')), [gol]);

    final back = StockItem.fromJson(gol.toJson());
    expect(back.applications.single.yearTo, 2016);
    expect(back.sku, 'P-0007');

    // posição no nome
    expect(withSide('Farol', 'esquerdo'), 'Farol esquerdo');
    expect(withSide('Farol esquerdo', 'dianteiro'), 'Farol dianteiro esquerdo');
    expect(withSide('Porta traseira', 'direito'), 'Porta traseira direita');
    expect(withSide('Porta dianteira direita', 'traseiro'), 'Porta traseira direita');
    expect(withSide('Farol esquerdo', 'esquerdo'), 'Farol');
  });
}
