// Cálculos do financeiro: fluxo de caixa, gastos por categoria e lucro.
import 'calc.dart';
import 'models.dart';

/// Orçamento "fechado": aprovado, em reparo, concluído ou entregue.
bool isClosedStatus(ClaimStatus s) =>
    s == ClaimStatus.aprovado ||
    s == ClaimStatus.emReparo ||
    s == ClaimStatus.concluido ||
    s == ClaimStatus.entregue;

/// Data em que o orçamento entra como receita.
DateTime closedDate(Claim c) => c.approvedAt ?? c.updatedAt;

const monthNames = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
];

/// Período [start, end).
class Period {
  final DateTime start;
  final DateTime end;
  final bool isYear;
  const Period(this.start, this.end, {this.isYear = false});

  factory Period.month(int year, int month) =>
      Period(DateTime(year, month), DateTime(year, month + 1));

  factory Period.year(int year) =>
      Period(DateTime(year), DateTime(year + 1), isYear: true);

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  Period previous() => isYear
      ? Period.year(start.year - 1)
      : Period.month(start.year, start.month - 1);

  Period next() => isYear
      ? Period.year(start.year + 1)
      : Period.month(start.year, start.month + 1);

  String get label => isYear
      ? '${start.year}'
      : '${monthNames[start.month - 1][0].toUpperCase()}${monthNames[start.month - 1].substring(1)} de ${start.year}';
}

enum CashKind { budget, income, expense }

/// Uma linha do fluxo de caixa.
class CashItem {
  final DateTime date;
  final String title;
  final String subtitle;
  final double amount; // positivo = entrada, negativo = saída
  final CashKind kind;
  final Claim? claim;
  final FinanceEntry? entry;

  const CashItem({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.kind,
    this.claim,
    this.entry,
  });
}

int _daysIn(int y, int m) => DateTime(y, m + 1, 0).day;

/// Datas em que um lançamento cai dentro do período (recorrentes repetem
/// todo mês no mesmo dia, a partir da data inicial).
List<DateTime> occurrences(FinanceEntry e, Period p) {
  if (!e.recurring) return p.contains(e.date) ? [e.date] : [];
  final out = <DateTime>[];
  var y = e.date.year, m = e.date.month;
  final until = e.recurringUntil;
  while (true) {
    final d = DateTime(y, m, e.date.day.clamp(1, _daysIn(y, m)));
    if (!d.isBefore(p.end)) break;
    if (until != null && d.isAfter(until)) break;
    if (p.contains(d)) out.add(d);
    m++;
    if (m > 12) {
      m = 1;
      y++;
    }
  }
  return out;
}

class FinanceSummary {
  final double closedBudgets;
  final int closedCount;
  final double otherIncome;
  final Map<ExpenseCategory, double> expensesByCategory;
  final List<CashItem> items; // ordenado por data

  const FinanceSummary({
    required this.closedBudgets,
    required this.closedCount,
    required this.otherIncome,
    required this.expensesByCategory,
    required this.items,
  });

  double get income => closedBudgets + otherIncome;
  double get expenses =>
      expensesByCategory.values.fold(0.0, (a, b) => a + b);
  double get profit => income - expenses;
  double get margin => income > 0 ? profit / income * 100 : 0;
  double get fixedExpenses => expensesByCategory[ExpenseCategory.fixo] ?? 0;
}

FinanceSummary summarize(
    List<Claim> claims, List<FinanceEntry> entries, Settings s, Period p) {
  final items = <CashItem>[];
  double closed = 0, other = 0;
  var closedCount = 0;
  final byCat = {for (final c in ExpenseCategory.values) c: 0.0};

  for (final c in claims) {
    if (!isClosedStatus(c.status)) continue;
    final d = closedDate(c);
    if (!p.contains(d)) continue;
    final total = computeTotals(c, s).total;
    closed += total;
    closedCount++;
    items.add(CashItem(
      date: d,
      title: 'Orçamento ${c.number}',
      subtitle: [
        if (c.vehicle.plate.isNotEmpty) c.vehicle.plate,
        if (c.customerName.isNotEmpty) c.customerName,
        c.status.label,
      ].join(' · '),
      amount: total,
      kind: CashKind.budget,
      claim: c,
    ));
  }

  for (final e in entries) {
    for (final d in occurrences(e, p)) {
      if (e.isIncome) {
        other += e.amount;
      } else {
        byCat[e.category] = byCat[e.category]! + e.amount;
      }
      items.add(CashItem(
        date: d,
        title: e.description.isEmpty ? e.categoryLabel : e.description,
        subtitle: [
          e.categoryLabel,
          if (e.contact.isNotEmpty) e.contact,
          if (e.recurring) 'mensal',
        ].join(' · '),
        amount: e.isIncome ? e.amount : -e.amount,
        kind: e.isIncome ? CashKind.income : CashKind.expense,
        entry: e,
      ));
    }
  }

  items.sort((a, b) => a.date.compareTo(b.date));
  return FinanceSummary(
    closedBudgets: closed,
    closedCount: closedCount,
    otherIncome: other,
    expensesByCategory: byCat,
    items: items,
  );
}

/// Gastos lançados vinculados a um sinistro (todas as datas).
double linkedCosts(Claim c, List<FinanceEntry> entries) => entries
    .where((e) => !e.isIncome && e.claimId == c.id)
    .fold(0.0, (a, e) => a + e.amount);
