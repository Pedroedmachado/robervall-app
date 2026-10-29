import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/calc.dart';
import 'package:funilar/format.dart';
import 'package:funilar/models.dart';

void main() {
  final s = Settings(
    laborRates: {
      LaborType.funilaria.name: 100,
      LaborType.mecanica.name: 120,
      LaborType.eletrica.name: 120,
      LaborType.tapecaria.name: 80,
      LaborType.vidracaria.name: 80,
    },
    paintRate: 90,
    paintMaterialRate: 50,
    totalLossPct: 75,
  );

  test('valores de um item de troca com MO e pintura', () {
    final it = BudgetItem(
      op: ItemOp.troca,
      qty: 2,
      price: 300,
      discountPct: 10,
      laborHours: 1.5,
      paintHours: 2,
    );
    final v = itemValues(it, s);
    expect(v.parts, closeTo(540, 0.001)); // 2*300 - 10%
    expect(v.labor, closeTo(150, 0.001));
    expect(v.paintLabor, closeTo(180, 0.001));
    expect(v.paintMaterial, closeTo(100, 0.001));
    expect(v.total, closeTo(970, 0.001));
  });

  test('reparo não cobra preço de peça', () {
    final it = BudgetItem(op: ItemOp.reparo, price: 999, laborHours: 3);
    final v = itemValues(it, s);
    expect(v.parts, 0);
    expect(v.total, closeTo(300, 0.001));
  });

  test('totais com franquia, desconto, itens não aprovados e FIPE', () {
    final c = Claim(
      type: ClaimType.seguradora,
      deductible: 1500,
      discountPct: 10,
      extraCosts: 200,
      vehicle: Vehicle(fipeValue: 10000),
      items: [
        BudgetItem(op: ItemOp.troca, price: 5000, laborHours: 2),
        BudgetItem(op: ItemOp.servico, price: 300),
        BudgetItem(op: ItemOp.troca, price: 9999, approved: false),
      ],
    );
    final t = computeTotals(c, s);
    // 5000 + 200 (MO) + 300 + 200 extra = 5700; -10% = 5130
    expect(t.subtotal, closeTo(5700, 0.001));
    expect(t.total, closeTo(5130, 0.001));
    expect(t.deductible, 1500);
    expect(t.insurerPays, closeTo(3630, 0.001));
    expect(t.customerPays, 1500);
    expect(t.rejectedCount, 1);
    expect(t.fipePct, closeTo(51.3, 0.001));
    expect(t.possibleTotalLoss, isFalse);
  });

  test('franquia maior que o total fica limitada', () {
    final c = Claim(
      type: ClaimType.seguradora,
      deductible: 5000,
      items: [BudgetItem(op: ItemOp.servico, price: 1000)],
    );
    final t = computeTotals(c, s);
    expect(t.deductible, 1000);
    expect(t.insurerPays, 0);
    expect(t.customerPays, 1000);
  });

  test('alerta de perda total', () {
    final c = Claim(
      vehicle: Vehicle(fipeValue: 10000),
      items: [BudgetItem(op: ItemOp.troca, price: 8000)],
    );
    final t = computeTotals(c, s);
    expect(t.possibleTotalLoss, isTrue);
    expect(t.customerPays, 8000);
  });

  test('json ida e volta preserva o sinistro', () {
    final c = Claim(
      number: 'FN-0007',
      type: ClaimType.terceiro,
      status: ClaimStatus.emReparo,
      customerName: 'João',
      dueDate: DateTime(2026, 11, 5),
      vehicle: Vehicle(plate: 'ABC-1D23', fipeValue: 45000.5),
      items: [BudgetItem(description: 'Capô', op: ItemOp.pintura, paintHours: 3)],
      damages: {'capo': 2},
      photos: [ClaimPhoto(fileName: 'a.jpg', caption: 'frente')],
      timeline: [TimelineEvent(text: 'ok', isStatus: true)],
    );
    final back = Claim.fromJson(c.toJson());
    expect(back.toJson(), c.toJson());
  });

  test('formatação brasileira', () {
    expect(money(1234567.891), 'R\$ 1.234.567,89');
    expect(money(-5), '-R\$ 5,00');
    expect(money(0.5), 'R\$ 0,50');
    expect(parseNum('1.234,56'), closeTo(1234.56, 0.0001));
    expect(parseNum('R\$ 10.000,00'), 10000);
    expect(parseNum('2.5'), 2.5);
    expect(num2(1.50), '1,5');
    expect(num2(3), '3');
    expect(plateMask('abc1d23'), 'ABC-1D23');
    expect(date(DateTime(2026, 3, 4)), '04/03/2026');
  });

  test('peças da mesma descrição viram uma linha só', () {
    final merged = mergePartLines([
      BudgetItem(description: 'Capô', op: ItemOp.reparo, laborHours: 3),
      BudgetItem(description: 'capô ', op: ItemOp.pintura, paintHours: 2),
      BudgetItem(description: 'Farol', op: ItemOp.troca, price: 400),
      BudgetItem(description: 'Farol', op: ItemOp.pintura, paintHours: 1),
      BudgetItem(description: 'Alinhamento', op: ItemOp.servico, price: 120),
    ]);
    expect(merged.length, 3);
    expect(merged[0].op, ItemOp.reparo);
    expect(merged[0].laborHours, 3);
    expect(merged[0].paintHours, 2);
    expect(merged[1].op, ItemOp.troca);
    expect(merged[1].price, 400);
    expect(merged[1].paintHours, 1);
    expect(opNames(merged[1].op, merged[1].laborHours, merged[1].paintHours),
        'Troca + pintura');
    expect(opDetails(ItemOp.reparo, 3, 2), ['Reparo 3 h', 'Pintura 2 h']);
    expect(opDetails(ItemOp.troca, 1.5, 0), ['Troca', 'Mão de obra 1,5 h']);
    expect(opFor(service: false, replace: false, laborHours: 0, paintHours: 2),
        ItemOp.pintura);
  });

  test('siglas das operações e legenda', () {
    expect(opCode(ItemOp.troca, 1, 0), 'T');
    expect(opCode(ItemOp.troca, 1, 4), 'T / P');
    expect(opCode(ItemOp.reparo, 2, 3), 'R / P');
    expect(opCode(ItemOp.reparo, 1, 4, removeInstall: true), 'R&I / P');
    expect(opCode(ItemOp.reparo, 1, 0, removeInstall: true), 'R&I');
    expect(opCode(ItemOp.pintura, 0, 2), 'P');
    expect(opCode(ItemOp.servico, 0, 0), 'S');
    final legend = legendFor([
      BudgetItem(op: ItemOp.troca, paintHours: 2),
      BudgetItem(op: ItemOp.reparo, laborHours: 1, removeInstall: true),
    ]);
    expect(legend.map((e) => e.$1), ['T', 'R&I', 'P']);
    final it = BudgetItem(op: ItemOp.reparo, laborHours: 1, removeInstall: true);
    expect(BudgetItem.fromJson(it.toJson()).removeInstall, isTrue);
  });

  test('mão de obra por peça: valor fechado, sem horas', () {
    final it = BudgetItem(
      description: 'Porta',
      op: ItemOp.reparo,
      perPiece: true,
      piecePrice: 350,
      doRepair: true,
      doPaint: true,
      laborHours: 5, // ignorado no modo por peça
    );
    final v = itemValues(it, s);
    expect(v.pieceLabor, 350);
    expect(v.labor, 0);
    expect(v.paintLabor, 0);
    expect(v.total, 350);
    expect(opCode(it.op, it.labFlag, it.paintFlag), 'R / P');
    expect(opDetails(it.op, it.labFlag, it.paintFlag, perPiece: true),
        ['Reparo', 'Pintura', 'Por peça']);

    final troca = BudgetItem(
        op: ItemOp.troca, price: 500, perPiece: true, piecePrice: 200, doPaint: true);
    expect(itemValues(troca, s).total, 700);
    expect(opCode(troca.op, troca.labFlag, troca.paintFlag), 'T / P');

    final c = Claim(items: [it, troca, BudgetItem(op: ItemOp.servico, price: 100)]);
    final t = computeTotals(c, s);
    expect(t.pieceLabor, 550);
    expect(t.laborHours, 0);
    expect(t.total, 1150);

    // ida e volta no JSON
    final back = BudgetItem.fromJson(it.toJson());
    expect(back.perPiece, isTrue);
    expect(back.piecePrice, 350);
    expect(back.doPaint, isTrue);
    expect(BudgetItem.fromJson(BudgetItem().toJson()).perPiece, isFalse);
  });

  test('R&I, reparo e pintura juntos, nessa ordem', () {
    expect(
        opCode(ItemOp.reparo, 1, 2, removeInstall: true, alsoRepair: true),
        'R&I / R / P');
    expect(
        opNames(ItemOp.reparo, 1, 2, removeInstall: true, alsoRepair: true),
        'Remoção e instalação + reparo + pintura');
    final it = BudgetItem(
        op: ItemOp.reparo,
        perPiece: true,
        piecePrice: 400,
        removeInstall: true,
        alsoRepair: true,
        doPaint: true);
    expect(legendFor([it]).map((e) => e.$1), ['R&I', 'R', 'P']);
    expect(
        opDetails(it.op, it.labFlag, it.paintFlag,
            removeInstall: true, alsoRepair: true, perPiece: true),
        ['Remoção e instalação', 'Reparo', 'Pintura', 'Por peça']);
    expect(BudgetItem.fromJson(it.toJson()).alsoRepair, isTrue);
  });
}
