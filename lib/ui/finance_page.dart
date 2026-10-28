import 'package:flutter/material.dart';

import '../finance.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import 'claims_page.dart';
import 'widgets.dart';

enum _View {
  flow('Fluxo de caixa'),
  expenses('Gastos'),
  income('Receitas');

  const _View(this.label);
  final String label;
}

const _income = Color(0xFF2E7D32);
const _expense = Color(0xFFC62828);

Color _catColor(ExpenseCategory c) {
  switch (c) {
    case ExpenseCategory.fixo:
      return const Color(0xFF5E35B1);
    case ExpenseCategory.fornecedor:
      return const Color(0xFF1E88E5);
    case ExpenseCategory.funcionario:
      return const Color(0xFF00897B);
    case ExpenseCategory.materiais:
      return const Color(0xFFEF6C00);
    case ExpenseCategory.impostos:
      return const Color(0xFF6D4C41);
    case ExpenseCategory.outros:
      return const Color(0xFF757575);
  }
}

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  late Period _period = Period.month(DateTime.now().year, DateTime.now().month);
  _View _view = _View.flow;

  Future<void> _newEntry({bool income = false}) async {
    final store = StoreScope.read(context);
    final now = DateTime.now();
    // lança dentro do período que está na tela
    final inPeriod = _period.contains(now)
        ? now
        : DateTime(_period.start.year, _period.start.month, 1);
    final e = await editFinanceEntry(
        context, FinanceEntry(isIncome: income, date: inPeriod));
    if (e != null) store.upsertEntry(e);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final sum = summarize(store.claims, store.entries, store.settings, _period);
    final t = Theme.of(context);

    final periodBar = Row(
      children: [
        IconButton(
          tooltip: 'Anterior',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => _period = _period.previous()),
        ),
        Expanded(
          child: Text(_period.label,
              textAlign: TextAlign.center,
              style: t.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        IconButton(
          tooltip: 'Próximo',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => _period = _period.next()),
        ),
      ],
    );

    final result = SectionCard(
      title: 'Resultado',
      icon: Icons.account_balance_wallet_outlined,
      children: [
        _Line('Orçamentos fechados (${sum.closedCount})', sum.closedBudgets,
            color: _income),
        if (sum.otherIncome > 0)
          _Line('Outras receitas', sum.otherIncome, color: _income),
        _Line('Gastos', -sum.expenses, color: _expense),
        const Divider(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(sum.profit >= 0 ? 'Lucro' : 'Prejuízo',
                  style: t.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Text(money(sum.profit),
                style: t.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: sum.profit >= 0 ? _income : _expense)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${money(sum.income)} de entradas − ${money(sum.expenses)} de gastos'
          '${sum.income > 0 ? ' · margem ${pct(sum.margin)}' : ''}',
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Orçamento fechado = aprovado, em reparo, concluído ou entregue, pela data da aprovação.',
          style: t.textTheme.bodySmall
              ?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
      ],
    );

    final cats = SectionCard(
      title: 'Gastos por categoria',
      icon: Icons.pie_chart_outline,
      children: [
        if (sum.expenses == 0)
          const Text('Nenhum gasto lançado neste período.')
        else
          for (final c in ExpenseCategory.values)
            if (sum.expensesByCategory[c]! > 0)
              _CatBar(
                label: c.label,
                value: sum.expensesByCategory[c]!,
                total: sum.expenses,
                color: _catColor(c),
              ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: () => _newEntry(),
            icon: const Icon(Icons.remove_circle_outline),
            label: const Text('Lançar gasto'),
          ),
          OutlinedButton.icon(
            onPressed: () => _newEntry(income: true),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Lançar receita'),
          ),
        ]),
      ],
    );

    Widget? yearCard;
    if (_period.isYear) {
      final rows = [
        for (var m = 1; m <= 12; m++)
          (
            m,
            summarize(store.claims, store.entries, store.settings,
                Period.month(_period.start.year, m))
          )
      ];
      final maxAbs = rows.fold<double>(
          1, (a, r) => [a, r.$2.income, r.$2.expenses].reduce((x, y) => x > y ? x : y));
      yearCard = SectionCard(
        title: 'Mês a mês',
        icon: Icons.calendar_month_outlined,
        children: [
          for (final (m, ms) in rows)
            _MonthRow(
              label: monthNames[m - 1].substring(0, 3),
              income: ms.income,
              expenses: ms.expenses,
              max: maxAbs,
            ),
        ],
      );
    }

    final list = _buildList(context, sum);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financeiro'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Mês')),
                ButtonSegment(value: true, label: Text('Ano')),
              ],
              selected: {_period.isYear},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                final y = _period.start.year;
                final now = DateTime.now();
                _period = s.first
                    ? Period.year(y)
                    : Period.month(y, y == now.year ? now.month : 1);
              }),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newEntry(),
        icon: const Icon(Icons.add),
        label: const Text('Lançar'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  periodBar,
                  const SizedBox(height: 8),
                  LayoutBuilder(builder: (context, cons) {
                    if (cons.maxWidth < 760) {
                      return Column(children: [result, cats]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: result),
                        const SizedBox(width: 12),
                        Expanded(child: cats),
                      ],
                    );
                  }),
                  if (yearCard != null) yearCard,
                  SegmentedButton<_View>(
                    segments: [
                      for (final v in _View.values)
                        ButtonSegment(value: v, label: Text(v.label)),
                    ],
                    selected: {_view},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _view = s.first),
                  ),
                  const SizedBox(height: 12),
                  list,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, FinanceSummary sum) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    switch (_view) {
      case _View.flow:
        if (sum.items.isEmpty) {
          return const EmptyState(
              icon: Icons.swap_vert,
              text: 'Sem entradas ou saídas neste período.');
        }
        var balance = 0.0;
        final rows = <Widget>[];
        for (final it in sum.items) {
          balance += it.amount;
          rows.add(_CashTile(item: it, balance: balance, onTap: () => _open(it)));
        }
        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: t.colorScheme.outlineVariant),
          ),
          child: Column(children: rows),
        );
      case _View.expenses:
        final exp = sum.items.where((i) => i.kind == CashKind.expense).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        if (exp.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            text:
                'Lance aqui aluguel, luz, salários, peças compradas de fornecedores, materiais e outros gastos.',
            action: FilledButton.icon(
              onPressed: () => _newEntry(),
              icon: const Icon(Icons.add),
              label: const Text('Lançar gasto'),
            ),
          );
        }
        return Column(children: [
          for (final it in exp) _CashTile(item: it, onTap: () => _open(it)),
        ]);
      case _View.income:
        final inc = sum.items.where((i) => i.kind != CashKind.expense).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        if (inc.isEmpty) {
          return const EmptyState(
              icon: Icons.request_quote_outlined,
              text:
                  'Nenhum orçamento fechado neste período. Quando um sinistro for aprovado, o valor entra aqui.');
        }
        return Column(children: [
          for (final it in inc)
            _CashTile(
              item: it,
              onTap: () => _open(it),
              extra: it.claim == null
                  ? null
                  : () {
                      final cost = linkedCosts(it.claim!, store.entries);
                      if (cost == 0) return null;
                      return 'Custos vinculados ${money(cost)} · lucro ${money(it.amount - cost)}';
                    }(),
            ),
        ]);
    }
  }

  Future<void> _open(CashItem it) async {
    final store = StoreScope.read(context);
    if (it.claim != null) {
      await openClaim(context, it.claim!);
      return;
    }
    final e = it.entry;
    if (e == null) return;
    final copy = FinanceEntry.fromJson(e.toJson());
    final r = await editFinanceEntry(context, copy, canDelete: true);
    if (r == null) return;
    final idx = store.entries.indexOf(e);
    if (r.id == '__delete__') {
      store.removeEntry(e);
      if (mounted) {
        showUndo(context, 'Lançamento excluído', () => store.upsertEntry(e));
      }
      return;
    }
    if (idx >= 0) store.entries[idx] = r;
    store.upsertEntry(r);
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(
            '${value < 0 ? '− ' : '+ '}${money(value.abs())}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ]),
      );
}

class _CatBar extends StatelessWidget {
  const _CatBar(
      {required this.label,
      required this.value,
      required this.total,
      required this.color});
  final String label;
  final double value, total;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(label)),
              Text(money(value),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : value / total,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      );
}

class _MonthRow extends StatelessWidget {
  const _MonthRow(
      {required this.label,
      required this.income,
      required this.expenses,
      required this.max});
  final String label;
  final double income, expenses, max;

  @override
  Widget build(BuildContext context) {
    final profit = income - expenses;
    Widget bar(double v, Color c) => ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: max <= 0 ? 0 : (v / max).clamp(0, 1).toDouble(),
            minHeight: 6,
            color: c,
            backgroundColor: c.withValues(alpha: 0.08),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 36, child: Text(label)),
          Expanded(
            child: Column(children: [
              bar(income, _income),
              const SizedBox(height: 2),
              bar(expenses, _expense),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(money(profit),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: profit >= 0 ? _income : _expense)),
          ),
        ],
      ),
    );
  }
}

class _CashTile extends StatelessWidget {
  const _CashTile(
      {required this.item, required this.onTap, this.balance, this.extra});
  final CashItem item;
  final VoidCallback onTap;
  final double? balance;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final positive = item.amount >= 0;
    final color = positive ? _income : _expense;
    final icon = switch (item.kind) {
      CashKind.budget => Icons.car_repair,
      CashKind.income => Icons.add_circle_outline,
      CashKind.expense => Icons.remove_circle_outline,
    };
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          date(item.date),
          item.subtitle,
          if (extra != null) extra!,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${positive ? '+' : '−'} ${money(item.amount.abs())}',
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          if (balance != null)
            Text('saldo ${money(balance!)}', style: t.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Editor de lançamento. Devolve o lançamento editado; com [canDelete],
/// devolve um lançamento com id "__delete__" quando a pessoa exclui.
Future<FinanceEntry?> editFinanceEntry(BuildContext context, FinanceEntry e,
    {bool canDelete = false}) {
  final store = StoreScope.read(context);
  return showFormDialog<FinanceEntry>(
    context: context,
    title: e.description.isEmpty
        ? (e.isIncome ? 'Nova receita' : 'Novo gasto')
        : 'Editar lançamento',
    onSave: () {
      if (e.amount <= 0) {
        toast(context, 'Informe o valor.');
        return null;
      }
      e.description = e.description.trim();
      if (e.description.isEmpty) e.description = e.categoryLabel;
      return e;
    },
    body: (ctx, setS) {
      final contactKinds = e.isIncome
          ? [ContactKind.cliente, ContactKind.seguradora]
          : e.category == ExpenseCategory.funcionario
              ? [ContactKind.funcionario]
              : [ContactKind.fornecedor, ContactKind.funcionario];
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  label: Text('Gasto'),
                  icon: Icon(Icons.remove_circle_outline)),
              ButtonSegment(
                  value: true,
                  label: Text('Receita'),
                  icon: Icon(Icons.add_circle_outline)),
            ],
            selected: {e.isIncome},
            onSelectionChanged: (s) => setS(() => e.isIncome = s.first),
          ),
          const SizedBox(height: 12),
          if (!e.isIncome) ...[
            Picker<ExpenseCategory>(
              label: 'Categoria',
              value: e.category,
              values: ExpenseCategory.values,
              labelOf: (c) => c.label,
              onChanged: (c) => setS(() {
                e.category = c;
                if (c == ExpenseCategory.fixo) e.recurring = true;
              }),
            ),
            const SizedBox(height: 12),
          ],
          BoundField(
            label: 'Descrição',
            value: e.description,
            hint: e.isIncome
                ? 'Ex.: venda de sucata'
                : 'Ex.: aluguel, salário, tinta, peças',
            onChanged: (t) => e.description = t,
          ),
          const SizedBox(height: 12),
          NumField(
            label: 'Valor',
            prefix: 'R\$',
            value: e.amount,
            onChanged: (n) => e.amount = n,
          ),
          const SizedBox(height: 12),
          DateField(
            label: e.recurring ? 'Primeiro mês (dia do vencimento)' : 'Data',
            value: e.date,
            onChanged: (d) => setS(() => e.date = d ?? DateTime.now()),
          ),
          const SizedBox(height: 12),
          BoundField(
            label: e.isIncome
                ? 'De quem (opcional)'
                : (e.category == ExpenseCategory.funcionario
                    ? 'Funcionário'
                    : 'Fornecedor / funcionário (opcional)'),
            value: e.contact,
            capitalization: TextCapitalization.words,
            suggestions: [
              for (final k in contactKinds)
                for (final c in store.contactsOf(k)) c.name
            ],
            onChanged: (t) => e.contact = t,
          ),
          const SizedBox(height: 12),
          Picker<String>(
            label: 'Vincular a um sinistro (opcional)',
            value: store.claimById(e.claimId) == null ? '' : e.claimId,
            values: ['', ...store.claims.map((c) => c.id)],
            labelOf: (id) {
              if (id.isEmpty) return 'Nenhum';
              final c = store.claimById(id)!;
              return '${c.number}${c.vehicle.plate.isEmpty ? '' : ' · ${c.vehicle.plate}'}';
            },
            onChanged: (id) => setS(() => e.claimId = id),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repetir todo mês'),
            subtitle: const Text('Para gastos fixos: aluguel, salário, internet…'),
            value: e.recurring,
            onChanged: (b) => setS(() => e.recurring = b),
          ),
          if (e.recurring)
            DateField(
              label: 'Até (opcional — vazio repete sempre)',
              value: e.recurringUntil,
              onChanged: (d) => setS(() => e.recurringUntil = d),
            ),
          const SizedBox(height: 12),
          BoundField(
            label: 'Observação',
            value: e.notes,
            maxLines: 2,
            onChanged: (t) => e.notes = t,
          ),
          if (canDelete) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(
                    ctx, FinanceEntry.fromJson(e.toJson())..id = '__delete__'),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Excluir lançamento'),
              ),
            ),
          ],
        ],
      );
    },
  );
}
