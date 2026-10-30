import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/cash.dart';
import 'package:funilar/finance.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/models.dart';
import 'package:funilar/store.dart';

void main() {
  test('orçamento concluído leva o lucro líquido para as entradas do caixa', () async {
    final store = await AppStore.open(
        assumeLicense: License.full(),
        dir: await Directory.systemTemp.createTemp('fn_caixa'));
    final c = store.newClaim()
      ..vehicle.plate = 'ABC-1D23'
      ..items = [BudgetItem(description: 'Porta', op: ItemOp.reparo, perPiece: true, piecePrice: 1000)];
    store.touch(c);
    store.upsertEntry(FinanceEntry(amount: 150, claimId: c.id, description: 'Guincho'));
    store.setStatus(c, ClaimStatus.aprovado);
    expect(store.cash, isEmpty); // aprovado ainda não é caixa
    store.setStatus(c, ClaimStatus.concluido);
    final e = store.cash.single;
    expect(e.isIn, isTrue);
    expect(e.amount, 850); // 1000 − 150
    expect(e.description, startsWith('Lucro líquido ${c.number}'));
    expect(e.autoKey, cashProfitKey);
    expect(c.concludedAt, isNotNull);
    // custo novo do carro atualiza o lucro no caixa
    store.upsertEntry(FinanceEntry(amount: 50, claimId: c.id, description: 'Fita'));
    expect(store.cash.single.amount, 800);
    // entregue continua lá; reabrir tira
    store.setStatus(c, ClaimStatus.entregue);
    expect(store.cash.length, 1);
    store.setStatus(c, ClaimStatus.emReparo);
    expect(store.cash, isEmpty);
    expect(c.concludedAt, isNull);
    // vendas (competência) não mudam: continua 1 orçamento fechado
    final sum = summarize(store.claims, store.entries, store.settings,
        Period.month(DateTime.now().year, DateTime.now().month));
    expect(sum.closedCount, 1);
  });

  test('entradas, saídas, previstos e saldo do período', () {
    final p = Period.month(2026, 10);
    final cash = [
      CashEntry(isIn: true, amount: 2000, date: DateTime(2026, 10, 5)),
      CashEntry(isIn: false, amount: 300, date: DateTime(2026, 10, 10), category: 'Energia'),
      CashEntry(isIn: false, amount: 1200, date: DateTime(2026, 10, 28), planned: true, category: 'Aluguel'),
      CashEntry(isIn: true, amount: 500, date: DateTime(2026, 10, 30), planned: true),
      CashEntry(isIn: true, amount: 999, date: DateTime(2026, 11, 2)), // outro mês
    ];
    final s = summarizeCash(cash, p);
    expect(s.entradas, 2000);
    expect(s.saidas, 300);
    expect(s.saldo, 1700);
    expect(s.previstoEntrar, 500);
    expect(s.previstoSair, 1200);
    expect(s.saldoPrevisto, 1000);
    expect(s.realized.length, 2);

    final up = upcoming(cash, now: DateTime(2026, 10, 29));
    expect(up.map((e) => e.amount), [1200, 500]); // atrasado + próximo
    expect(up.first.planned, isTrue);

    final aluguel = CashEntry(isIn: false, amount: 1200, date: DateTime(2026, 1, 31), planned: true);
    final copies = repeatMonthly(aluguel, 3);
    expect(copies.length, 2);
    expect(copies.first.date, DateTime(2026, 2, 31)); // vira 3 de março (Dart ajusta)
    final back = CashEntry.fromJson(aluguel.toJson());
    expect(back.planned, isTrue);
    expect(back.isIn, isFalse);
    expect(back.signed, -1200);
  });
}
