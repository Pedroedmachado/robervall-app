import 'package:flutter/material.dart';

import '../cash.dart';
import '../finance.dart';
import '../format.dart';
import '../models.dart';
import '../modules.dart';
import '../theme.dart';
import 'claims_page.dart';
import 'widgets.dart';

const _in = Color(0xFF2E7D32);
const _out = Color(0xFFC62828);
const _plan = Color(0xFF6D4C41);

enum _CashView {
  consolidado('Consolidado'),
  entradas('Entradas'),
  saidas('Saídas');

  const _CashView(this.label);
  final String label;
}

/// Sub-aba Caixa (regime de caixa): o dinheiro que entrou e saiu de verdade,
/// e os recebimentos/pagamentos previstos.
class CashView extends StatefulWidget {
  const CashView({super.key, required this.period, required this.header});
  final Period period;
  final Widget header;

  @override
  State<CashView> createState() => _CashViewState();
}

class _CashViewState extends State<CashView> {
  _CashView _view = _CashView.consolidado;

  Future<void> _new({required bool isIn, bool planned = false}) async {
    final store = StoreScope.read(context);
    final now = DateTime.now();
    final p = widget.period;
    final day = p.contains(now) || planned ? now : p.start;
    final e = CashEntry(
      isIn: isIn,
      planned: planned,
      date: planned ? DateTime(day.year, day.month, day.day + 7) : day,
      category: isIn ? cashInCategories.first : cashOutCategories.first,
    );
    final r = await editCashEntry(context, e);
    if (r == null) return;
    store.upsertCash(r.$1);
    for (final c in repeatMonthly(r.$1, r.$2)) {
      store.upsertCash(c);
    }
  }

  Future<void> _open(CashEntry e) async {
    final store = StoreScope.read(context);
    if (e.autoKey == cashProfitKey) {
      final c = store.claimById(e.claimId);
      if (c != null) {
        toast(context, 'Lucro automático do orçamento concluído: ajuste custos no sinistro.');
        await openClaim(context, c);
      }
      return;
    }
    if (!gate.can(Perm.financeiroEditar)) return;
    final copy = CashEntry.fromJson(e.toJson());
    final r = await editCashEntry(context, copy, canDelete: true);
    if (r == null || !mounted) return;
    if (r.$1.id == '__delete__') {
      store.removeCash(e);
      showUndo(context, 'Lançamento do caixa excluído', () => store.upsertCash(e));
      return;
    }
    final i = store.cash.indexOf(e);
    if (i >= 0) store.cash[i] = r.$1;
    store.upsertCash(r.$1);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final sum = summarizeCash(store.cash, widget.period);
    final next = upcoming(store.cash);
    final canEdit = gate.can(Perm.financeiroEditar);

    Widget line(String label, double v, Color c, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: bold ? const TextStyle(fontWeight: FontWeight.w800) : null)),
            Text(money(v),
                style: TextStyle(
                    color: c, fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                    fontSize: bold ? 18 : null)),
          ]),
        );

    final resumo = SectionCard(
      title: 'Caixa do período',
      icon: Icons.point_of_sale_outlined,
      children: [
        line('Entradas', sum.entradas, _in),
        line('Saídas', -sum.saidas, _out),
        const Divider(height: 16),
        line(sum.saldo >= 0 ? 'Saldo' : 'Saldo negativo', sum.saldo,
            sum.saldo >= 0 ? _in : _out,
            bold: true),
        if (sum.previstoEntrar > 0 || sum.previstoSair > 0) ...[
          const SizedBox(height: 8),
          line('Recebimentos previstos', sum.previstoEntrar, _in),
          line('Pagamentos previstos', -sum.previstoSair, _out),
          line('Saldo previsto do período', sum.saldoPrevisto,
              sum.saldoPrevisto >= 0 ? _in : _out),
        ],
        const SizedBox(height: 4),
        Text('Só o dinheiro que entrou e saiu de verdade (regime de caixa). Vendas e custos por competência ficam na aba Vendas.',
            style: t.textTheme.bodySmall),
        if (canEdit) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: () => _new(isIn: true),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Entrada'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _new(isIn: false),
              icon: const Icon(Icons.remove_circle_outline),
              label: const Text('Saída'),
            ),
          ]),
        ],
      ],
    );

    final previstos = SectionCard(
      title: 'Previstos (próximos 30 dias)',
      icon: Icons.event_note_outlined,
      children: [
        if (next.isEmpty)
          const Text('Nada previsto. Lance recebimentos e pagamentos que vão acontecer para não ser pego de surpresa.')
        else
          for (final e in next)
            _PlannedTile(
              e: e,
              onTap: () => _open(e),
              onConfirm: !canEdit
                  ? null
                  : () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        helpText: e.isIn ? 'Recebido em' : 'Pago em',
                      );
                      if (d == null || !context.mounted) return;
                      store.confirmPlanned(e, on: d);
                      toast(context,
                          '${e.isIn ? 'Recebimento' : 'Pagamento'} confirmado no caixa.');
                    },
            ),
        if (canEdit) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => _new(isIn: true, planned: true),
              icon: const Icon(Icons.call_received, color: _in),
              label: const Text('Recebimento previsto'),
            ),
            OutlinedButton.icon(
              onPressed: () => _new(isIn: false, planned: true),
              icon: const Icon(Icons.call_made, color: _out),
              label: const Text('Pagamento previsto'),
            ),
          ]),
        ],
      ],
    );

    final items = switch (_view) {
      _CashView.consolidado => sum.realized,
      _CashView.entradas => sum.realized.where((e) => e.isIn).toList(),
      _CashView.saidas => sum.realized.where((e) => !e.isIn).toList(),
    };
    Widget list;
    if (items.isEmpty) {
      list = EmptyState(
        icon: Icons.swap_vert,
        text: switch (_view) {
          _CashView.consolidado => 'Sem entradas ou saídas neste período.',
          _CashView.entradas =>
            'Lance aqui o dinheiro recebido (dinheiro, Pix, cheque…). O lucro de cada orçamento concluído entra sozinho.',
          _CashView.saidas =>
            'Lance aqui o que foi pago: água, energia, aluguel, internet…',
        },
      );
    } else {
      var balance = 0.0;
      final rows = <Widget>[];
      final ordered = _view == _CashView.consolidado
          ? items
          : (items.toList()..sort((a, b) => b.date.compareTo(a.date)));
      for (final e in ordered) {
        balance += e.signed;
        rows.add(_CashEntryTile(
          e: e,
          balance: _view == _CashView.consolidado ? balance : null,
          onTap: () => _open(e),
        ));
      }
      list = Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: t.colorScheme.outlineVariant),
        ),
        child: Column(children: rows),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.header,
                const SizedBox(height: 8),
                LayoutBuilder(builder: (context, cons) {
                  if (cons.maxWidth < 760) {
                    return Column(children: [resumo, previstos]);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: resumo),
                      const SizedBox(width: 12),
                      Expanded(child: previstos),
                    ],
                  );
                }),
                SegmentedButton<_CashView>(
                  segments: [
                    for (final v in _CashView.values)
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
    );
  }
}

class _CashEntryTile extends StatelessWidget {
  const _CashEntryTile({required this.e, required this.onTap, this.balance});
  final CashEntry e;
  final VoidCallback onTap;
  final double? balance;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = e.signed >= 0 ? _in : _out;
    return ListTile(
      key: ValueKey('caixa-${e.id}'),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(
            e.autoKey == cashProfitKey
                ? Icons.car_repair
                : (e.isIn ? Icons.call_received : Icons.call_made),
            color: color,
            size: 20),
      ),
      title: Text(e.description.isEmpty ? e.category : e.description,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          date(e.date),
          e.category,
          if (e.autoKey != cashProfitKey) e.method.label,
          if (e.contact.isNotEmpty) e.contact,
          if (e.autoKey == cashProfitKey) 'automático',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${e.signed >= 0 ? '+' : '−'} ${money(e.signed.abs())}',
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          if (balance != null)
            Text('saldo ${money(balance!)}', style: t.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PlannedTile extends StatelessWidget {
  const _PlannedTile({required this.e, required this.onTap, this.onConfirm});
  final CashEntry e;
  final VoidCallback onTap;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final color = e.isIn ? _in : _out;
    return ListTile(
      key: ValueKey('previsto-${e.id}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: onTap,
      leading: Icon(e.isIn ? Icons.call_received : Icons.call_made, color: color),
      title: Text(e.description.isEmpty ? e.category : e.description,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${e.isIn ? 'Receber' : 'Pagar'} em ${date(e.date)}${e.overdue ? ' · ATRASADO' : ''}',
        style: TextStyle(
            color: e.overdue ? _out : _plan,
            fontWeight: e.overdue ? FontWeight.w700 : null),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(money(e.amount),
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        if (onConfirm != null)
          IconButton(
            tooltip: e.isIn ? 'Recebi' : 'Paguei',
            icon: const Icon(Icons.check_circle_outline),
            onPressed: onConfirm,
          ),
      ]),
    );
  }
}

/// Lançamento do caixa. Devolve (lançamento, meses para repetir).
Future<(CashEntry, int)?> editCashEntry(BuildContext context, CashEntry e,
    {bool canDelete = false}) {
  final store = StoreScope.read(context);
  var months = 1;
  return showFormDialog<(CashEntry, int)>(
    context: context,
    title: e.description.isEmpty
        ? (e.planned
            ? (e.isIn ? 'Recebimento previsto' : 'Pagamento previsto')
            : (e.isIn ? 'Entrada no caixa' : 'Saída do caixa'))
        : 'Editar lançamento do caixa',
    onSave: () {
      if (e.amount <= 0) {
        toast(context, 'Informe o valor.');
        return null;
      }
      e.description = e.description.trim();
      if (e.description.isEmpty) e.description = e.category;
      return (e, e.planned ? months : 1);
    },
    body: (ctx, setS) {
      final cats = e.isIn ? cashInCategories : cashOutCategories;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Entrada'), icon: Icon(Icons.call_received)),
              ButtonSegment(value: false, label: Text('Saída'), icon: Icon(Icons.call_made)),
            ],
            selected: {e.isIn},
            onSelectionChanged: (s) => setS(() {
              e.isIn = s.first;
              e.category = (e.isIn ? cashInCategories : cashOutCategories).first;
            }),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Já aconteceu')),
              ButtonSegment(value: true, label: Text('Previsto')),
            ],
            selected: {e.planned},
            onSelectionChanged: (s) => setS(() => e.planned = s.first),
          ),
          const SizedBox(height: 12),
          Text('Categoria', style: Theme.of(ctx).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final c in {...cats, if (e.category.isNotEmpty) e.category})
              ChoiceChip(
                label: Text(c),
                selected: e.category == c,
                onSelected: (_) => setS(() => e.category = c),
              ),
          ]),
          const SizedBox(height: 12),
          BoundField(
            label: 'Descrição',
            hint: e.isIn ? 'Ex.: recebido do cliente Ana' : 'Ex.: conta de luz de outubro',
            value: e.description,
            onChanged: (v) => e.description = v,
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
            label: e.planned
                ? (e.isIn ? 'Data prevista para receber' : 'Vencimento')
                : (e.isIn ? 'Recebido em' : 'Pago em'),
            value: e.date,
            onChanged: (d) => setS(() => e.date = d ?? DateTime.now()),
          ),
          const SizedBox(height: 12),
          Text('Forma', style: Theme.of(ctx).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final m in CashMethod.values)
              ChoiceChip(
                label: Text(m.label),
                selected: e.method == m,
                onSelected: (_) => setS(() => e.method = m),
              ),
          ]),
          const SizedBox(height: 12),
          BoundField(
            label: e.isIn ? 'De quem (opcional)' : 'Para quem (opcional)',
            value: e.contact,
            capitalization: TextCapitalization.words,
            suggestions: [for (final c in store.contacts) c.name],
            onChanged: (v) => e.contact = v,
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
          if (e.planned && !canDelete) ...[
            const SizedBox(height: 12),
            NumField(
              label: 'Repetir por quantos meses',
              suffix: 'meses',
              value: months.toDouble(),
              onChanged: (n) => months = n < 1 ? 1 : (n > 36 ? 36 : n.round()),
            ),
            Text('Ex.: aluguel → 12 cria um previsto por mês.',
                style: Theme.of(ctx).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          BoundField(
            label: 'Observação',
            value: e.notes,
            maxLines: 2,
            onChanged: (v) => e.notes = v,
          ),
          if (canDelete) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(
                    ctx, (CashEntry.fromJson(e.toJson())..id = '__delete__', 1)),
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
