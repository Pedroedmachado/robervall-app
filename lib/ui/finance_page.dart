import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../finance.dart';
import '../format.dart';
import '../models.dart';
import '../receipt_ocr.dart';
import '../receipt_parser.dart';
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

  /// Foto da nota → lê valor, data, loja e itens → abre para conferir.
  Future<void> _readReceipt() async {
    final store = StoreScope.read(context);
    final scan = await scanReceiptPhoto(context);
    if (scan == null || !mounted) return;
    final entry = FinanceEntry(receiptFile: scan.file);
    scan.data?.applyTo(entry);
    final saved =
        await editFinanceEntry(context, entry, banner: scan.message);
    if (saved == null) {
      final f = File('${store.photosDir.path}/${scan.file}');
      if (await f.exists()) await f.delete();
      return;
    }
    store.upsertEntry(saved);
    if (!_period.contains(saved.date) && mounted) {
      setState(() =>
          _period = Period.month(saved.date.year, saved.date.month));
    }
    if (mounted) toast(context, 'Gasto lançado em ${date(saved.date)}.');
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
            if (sum.expensesByCategory[c]! > 0) ...[
              _CatBar(
                label: c.label,
                value: sum.expensesByCategory[c]!,
                total: sum.expenses,
                color: _catColor(c),
              ),
              if (c == ExpenseCategory.funcionario)
                for (final w in sum.workerBreakdown.entries)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 2),
                    child: Row(children: [
                      Icon(Icons.subdirectory_arrow_right,
                          size: 14, color: t.colorScheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(w.key, style: t.textTheme.bodySmall)),
                      Text(money(w.value), style: t.textTheme.bodySmall),
                    ]),
                  ),
            ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _readReceipt,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Ler nota (foto)'),
          ),
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
    if (e.autoKey.isNotEmpty) {
      // custo gerado pelo orçamento (pintor): edita-se no sinistro
      final claim = store.claimById(e.claimId);
      if (claim != null) {
        toast(context, 'Custo automático do pintor: ajuste no orçamento do sinistro.');
        await openClaim(context, claim);
      }
      return;
    }
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

/// Ganchos para os testes (escolher a foto e ler o texto sem câmera/ML Kit).
@visibleForTesting
Future<String?> Function(BuildContext context)? debugPickReceipt;
@visibleForTesting
Future<List<String>> Function(String path)? debugReadReceipt;

/// Resultado de anexar a foto de uma nota.
class ReceiptScan {
  const ReceiptScan(this.file, this.data, this.message);

  /// Nome do arquivo salvo na pasta de fotos.
  final String file;

  /// O que foi lido (null quando não deu para ler).
  final ReceiptData? data;

  /// Aviso para mostrar no lançamento.
  final String message;
}

/// Pede a foto da nota (câmera ou galeria), guarda junto dos lançamentos e,
/// no celular, lê sozinho loja, data, nº da nota, itens, pagamento e total.
Future<ReceiptScan?> scanReceiptPhoto(BuildContext context) async {
  final store = StoreScope.read(context);
  String? path;
  if (debugPickReceipt != null) {
    path = await debugPickReceipt!(context);
  } else {
    final mobile = Platform.isAndroid || Platform.isIOS;
    ImageSource? source = ImageSource.gallery;
    if (mobile) {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto da nota'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ]),
        ),
      );
    }
    if (source == null || !context.mounted) return null;
    try {
      final f = await ImagePicker()
          .pickImage(source: source, maxWidth: 2400, imageQuality: 90);
      path = f?.path;
    } catch (e) {
      if (context.mounted) toast(context, 'Não foi possível abrir a foto: $e');
      return null;
    }
  }
  if (path == null || !context.mounted) return null;

  // guarda a foto junto dos lançamentos
  final name = 'nota_${newId()}.jpg';
  await File('${store.photosDir.path}/$name')
      .writeAsBytes(await File(path).readAsBytes(), flush: true);

  final reader = debugReadReceipt ??
      (receiptOcrAvailable ? readReceiptLines : null);
  if (reader == null) {
    return ReceiptScan(name, null,
        'A leitura automática funciona no celular. Aqui a foto fica anexada e você preenche os valores.');
  }
  if (!context.mounted) return null;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
        SizedBox(width: 16),
        Expanded(child: Text('Lendo a nota…')),
      ]),
    ),
  );
  ReceiptScan scan;
  try {
    final data = parseReceipt(await reader(path));
    final n = data.items.length;
    scan = ReceiptScan(
      name,
      data,
      data.total > 0
          ? 'Nota lida: ${[
              if (data.docNumber.isNotEmpty) data.docNumber,
              '$n ${n == 1 ? 'item' : 'itens'}',
              'total ${money(data.total)}',
            ].join(' · ')}. Resumo preenchido abaixo — confira antes de salvar.'
          : 'Não consegui achar o total nesta foto. Preencha o valor (a foto fica anexada).',
    );
  } catch (e) {
    scan = ReceiptScan(name, null,
        'Não consegui ler a nota ($e). Preencha à mão; a foto fica anexada.');
  }
  if (context.mounted) Navigator.of(context).pop(); // fecha "Lendo a nota…"
  return scan;
}

/// Editor de lançamento. Devolve o lançamento editado; com [canDelete],
/// devolve um lançamento com id "__delete__" quando a pessoa exclui.
Future<FinanceEntry?> editFinanceEntry(BuildContext context, FinanceEntry e,
    {bool canDelete = false, String? banner}) {
  final store = StoreScope.read(context);
  var note = banner;
  return showFormDialog<FinanceEntry>(
    context: context,
    title: e.description.isEmpty
        ? (e.isIncome ? 'Nova receita' : 'Novo gasto')
        : 'Editar lançamento',
    onSave: () {
      e.syncPieceAmount();
      if (e.amount <= 0) {
        toast(context, 'Informe o valor.');
        return null;
      }
      e.description = e.description.trim();
      if (e.description.isEmpty) {
        e.description = e.isWorker
            ? [e.workerLabel, if (e.contact.trim().isNotEmpty) e.contact.trim()]
                .join(' · ')
            : e.categoryLabel;
      }
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
          if (note != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.document_scanner_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(note!)),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          if (e.receiptFile.isNotEmpty) ...[
            _ReceiptThumb(
                file: File('${store.photosDir.path}/${e.receiptFile}')),
            const SizedBox(height: 8),
          ],
          if (!e.isIncome) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final scan = await scanReceiptPhoto(ctx);
                  if (scan == null) return;
                  setS(() {
                    e.receiptFile = scan.file;
                    scan.data?.applyTo(e);
                    note = scan.message;
                  });
                },
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(e.receiptFile.isEmpty
                    ? 'Anexar foto da nota'
                    : 'Trocar foto da nota'),
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                if (c == ExpenseCategory.funcionario) {
                  e.recurring = !e.outsourced && e.payType == PayType.salario;
                }
              }),
            ),
            const SizedBox(height: 12),
          ],
          if (e.isWorker) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('Funcionário'),
                    icon: Icon(Icons.badge_outlined)),
                ButtonSegment(
                    value: true,
                    label: Text('Terceirizado'),
                    icon: Icon(Icons.handshake_outlined)),
              ],
              selected: {e.outsourced},
              onSelectionChanged: (sel) => setS(() {
                e.outsourced = sel.first;
                if (e.outsourced && e.payType == PayType.salario) {
                  e.payType = PayType.empreita;
                }
                e.recurring = !e.outsourced && e.payType == PayType.salario;
              }),
            ),
            const SizedBox(height: 12),
            if (e.outsourced) ...[
              Picker<OutsourcedService>(
                label: 'Serviço terceirizado',
                value: e.service,
                values: OutsourcedService.values,
                labelOf: (v) => v.label,
                onChanged: (v) => setS(() => e.service = v),
              ),
              const SizedBox(height: 12),
            ],
            Text('Forma de pagamento',
                style: Theme.of(ctx).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final pt in PayType.values)
                if (!(e.outsourced && pt == PayType.salario))
                  ChoiceChip(
                    label: Text(pt.label),
                    selected: e.payType == pt,
                    onSelected: (_) => setS(() {
                      e.payType = pt;
                      e.recurring = !e.outsourced && pt == PayType.salario;
                      e.syncPieceAmount();
                    }),
                  ),
            ]),
            const SizedBox(height: 12),
          ],
          BoundField(
            label: 'Descrição',
            value: e.description,
            hint: e.isIncome
                ? 'Ex.: venda de sucata'
                : (e.isWorker
                    ? 'Ex.: pintura do Gol, salário de outubro'
                    : 'Ex.: aluguel, tinta, peças'),
            onChanged: (t) => e.description = t,
          ),
          const SizedBox(height: 12),
          if (e.paidByPiece) ...[
            Row(children: [
              Expanded(
                child: NumField(
                  label: 'Nº de peças',
                  value: e.pieces,
                  onChanged: (n) => setS(() {
                    e.pieces = n;
                    e.syncPieceAmount();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumField(
                  label: 'Valor por peça',
                  prefix: 'R\$',
                  value: e.pieceValue,
                  onChanged: (n) => setS(() {
                    e.pieceValue = n;
                    e.syncPieceAmount();
                  }),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              '${num2(e.pieces)} ${e.pieces == 1 ? 'peça' : 'peças'} × ${money(e.pieceValue)} = ${money(e.amount)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ] else
            NumField(
              label: e.isWorker && e.payType == PayType.empreita
                  ? 'Valor da empreita'
                  : (e.isWorker && e.payType == PayType.salario
                      ? 'Salário'
                      : 'Valor'),
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
                    ? (e.outsourced ? 'Prestador / terceirizado' : 'Funcionário')
                    : 'Fornecedor / funcionário (opcional)'),
            value: e.contact,
            capitalization: TextCapitalization.words,
            suggestions: [
              for (final k in contactKinds)
                for (final c in store.contactsOf(k)) c.name
            ],
            onChanged: (t) {
              e.contact = t;
              // funcionário cadastrado: puxa modalidade e valor combinados
              if (!e.isWorker) return;
              final match = store.contactsOf(ContactKind.funcionario).where(
                  (w) => w.name.toLowerCase() == t.trim().toLowerCase());
              if (match.isEmpty) return;
              final w = match.first;
              setS(() {
                e.outsourced = w.outsourced;
                e.service = w.service;
                e.payType = w.payType;
                e.recurring = !w.outsourced && w.payType == PayType.salario;
                if (w.payType == PayType.porPeca) {
                  e.pieceValue = w.rate;
                  e.syncPieceAmount();
                } else if (w.rate > 0) {
                  e.amount = w.rate;
                }
              });
            },
          ),
          if (!e.isIncome) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: BoundField(
                  label: 'Nº da nota / fatura',
                  value: e.invoiceNumber,
                  onChanged: (t) => e.invoiceNumber = t,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BoundField(
                  label: 'Pagamento',
                  value: e.paymentMethod,
                  hint: 'À vista, Pix, cartão…',
                  suggestions: const [
                    'À vista',
                    'Pix',
                    'Dinheiro',
                    'Cartão de débito',
                    'Cartão de crédito',
                    'Boleto',
                    'A prazo',
                  ],
                  onChanged: (t) => e.paymentMethod = t,
                ),
              ),
            ]),
          ],
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
            label: e.receiptFile.isEmpty
                ? 'Observação'
                : 'Resumo da nota / observação',
            value: e.notes,
            maxLines: e.receiptFile.isEmpty ? 2 : 6,
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


/// Miniatura da nota anexada; toque para ver inteira.
class _ReceiptThumb extends StatelessWidget {
  const _ReceiptThumb({required this.file});
  final File file;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Stack(children: [
            InteractiveViewer(
              maxScale: 6,
              child: Image.file(file,
                  errorBuilder: (_, __, ___) =>
                      const Padding(padding: EdgeInsets.all(32), child: Icon(Icons.broken_image))),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton.filledTonal(
                tooltip: 'Fechar',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ]),
        ),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 64,
            height: 84,
            child: Image.file(file,
                fit: BoxFit.cover,
                cacheWidth: 200,
                errorBuilder: (_, __, ___) => const Icon(Icons.receipt_long)),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Text('Foto da nota anexada · toque para ver')),
      ]),
    );
  }
}
