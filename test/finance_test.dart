import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/finance.dart';
import 'package:funilar/models.dart';

void main() {
  final s = Settings();

  Claim closed(double value, DateTime approved,
          {ClaimStatus status = ClaimStatus.entregue}) =>
      Claim(
        status: status,
        approvedAt: approved,
        items: [BudgetItem(op: ItemOp.servico, price: value)],
      );

  test('lucro = orçamentos fechados − gastos do mês', () {
    final claims = [
      closed(5000, DateTime(2026, 10, 5)),
      closed(3000, DateTime(2026, 10, 20), status: ClaimStatus.emReparo),
      closed(9999, DateTime(2026, 9, 30)), // outro mês
      Claim(
          status: ClaimStatus.orcamento, // não fechado
          approvedAt: DateTime(2026, 10, 2),
          items: [BudgetItem(op: ItemOp.servico, price: 777)]),
    ];
    final entries = [
      FinanceEntry(
          date: DateTime(2026, 1, 10),
          amount: 2000,
          category: ExpenseCategory.fixo,
          recurring: true), // aluguel desde janeiro
      FinanceEntry(
          date: DateTime(2026, 10, 15),
          amount: 1200,
          category: ExpenseCategory.fornecedor),
      FinanceEntry(
          date: DateTime(2026, 10, 16),
          amount: 300,
          isIncome: true), // receita avulsa
      FinanceEntry(
          date: DateTime(2026, 11, 1),
          amount: 500,
          category: ExpenseCategory.materiais), // outro mês
    ];
    final sum = summarize(claims, entries, s, Period.month(2026, 10));
    expect(sum.closedCount, 2);
    expect(sum.closedBudgets, 8000);
    expect(sum.otherIncome, 300);
    expect(sum.expensesByCategory[ExpenseCategory.fixo], 2000);
    expect(sum.expensesByCategory[ExpenseCategory.fornecedor], 1200);
    expect(sum.expenses, 3200);
    expect(sum.profit, 8000 + 300 - 3200);
    // fluxo em ordem de data
    expect(sum.items.first.date, DateTime(2026, 10, 5));
    expect(sum.items.map((e) => e.amount).reduce((a, b) => a + b), sum.profit);
  });

  test('gasto fixo repete todo mês até a data final', () {
    final e = FinanceEntry(
        date: DateTime(2026, 1, 31),
        amount: 100,
        recurring: true,
        recurringUntil: DateTime(2026, 4, 30));
    final year = occurrences(e, Period.year(2026));
    expect(year.length, 4); // jan, fev, mar, abr
    expect(year[1], DateTime(2026, 2, 28)); // dia ajustado ao fim do mês
    expect(occurrences(e, Period.month(2025, 12)), isEmpty);
    expect(occurrences(e, Period.month(2026, 5)), isEmpty);
  });

  test('ano soma os 12 meses', () {
    final entries = [
      FinanceEntry(
          date: DateTime(2026, 3, 5),
          amount: 1000,
          category: ExpenseCategory.funcionario,
          recurring: true),
    ];
    final sum = summarize([], entries, s, Period.year(2026));
    expect(sum.expenses, 10 * 1000); // março a dezembro
    expect(sum.profit, -10000);
    expect(Period.month(2026, 12).next().label, 'Janeiro de 2027');
  });

  test('lançamento ida e volta em JSON', () {
    final e = FinanceEntry(
      amount: 50.5,
      description: 'Internet',
      category: ExpenseCategory.fixo,
      recurring: true,
      recurringUntil: DateTime(2027, 1, 1),
      contact: 'Provedor',
      claimId: 'x',
    );
    expect(FinanceEntry.fromJson(e.toJson()).toJson(), e.toJson());
  });

  test('funcionários: salário, por peça e terceirizado', () {
    final pecas = FinanceEntry(
        date: DateTime(2026, 10, 10),
        category: ExpenseCategory.funcionario,
        payType: PayType.porPeca,
        pieces: 12,
        pieceValue: 35,
        contact: 'João pintor')
      ..syncPieceAmount();
    expect(pecas.amount, 420);
    final entries = [
      pecas,
      FinanceEntry(
          date: DateTime(2026, 1, 5),
          category: ExpenseCategory.funcionario,
          payType: PayType.salario,
          amount: 2000,
          recurring: true),
      FinanceEntry(
          date: DateTime(2026, 10, 12),
          category: ExpenseCategory.funcionario,
          outsourced: true,
          service: OutsourcedService.funilaria,
          payType: PayType.empreita,
          amount: 800),
    ];
    final sum = summarize([], entries, s, Period.month(2026, 10));
    expect(sum.expensesByCategory[ExpenseCategory.funcionario], 3220);
    expect(sum.workerBreakdown, {
      'Por peça': 420,
      'Salário': 2000,
      'Terceirizado · Funilaria': 800,
    });
    expect(sum.items.any((i) => i.subtitle.contains('12 peças')), isTrue);
    final back = FinanceEntry.fromJson(pecas.toJson());
    expect(back.payType, PayType.porPeca);
    expect(back.pieces, 12);
    expect(back.pieceValue, 35);
  });
}
