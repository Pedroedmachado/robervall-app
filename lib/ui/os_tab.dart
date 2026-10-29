import 'package:flutter/material.dart';

import '../finance.dart';
import '../format.dart';
import '../models.dart';
import '../seed.dart';
import '../stock.dart';
import '../theme.dart';
import 'access.dart';
import 'stock_page.dart' show StockThumb;
import 'widgets.dart';

/// Ordem de serviço: o que fazer no carro, peças, insumos e equipe.
/// No modo produção não mostra valores; no modo gestor mostra o custo real.
class OsTab extends StatelessWidget {
  const OsTab({super.key, required this.claim});
  final Claim claim;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = claim;
    final t = Theme.of(context);
    final production = store.settings.productionMode;
    final tasks = c.items.where((i) => i.approved).toList();
    final doneCount = tasks.where((i) => i.done).length;
    final parts = tasks.where((i) => i.op == ItemOp.troca).toList();
    final clientParts = store.stock
        .where((s) => s.kind == StockKind.cliente && s.claimId == c.id)
        .toList();
    final byItem = <String, List<SupplyUse>>{};
    for (final u in c.supplies) {
      byItem.putIfAbsent(u.itemId, () => []).add(u);
    }

    String itemName(String id) {
      for (final i in c.items) {
        if (i.id == id) return i.description;
      }
      return '';
    }

    final children = <Widget>[
      if (!production) _CostCard(claim: c),
      SectionCard(
        title: 'Tarefas ($doneCount de ${tasks.length})',
        icon: Icons.checklist,
        children: [
          if (tasks.isEmpty)
            const Text('Nenhum item aprovado no orçamento ainda.')
          else ...[
            LinearProgressIndicator(
              value: tasks.isEmpty ? 0 : doneCount / tasks.length,
              minHeight: 6,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(height: 6),
            for (final it in tasks)
              CheckboxListTile(
                key: ValueKey('task-${it.id}'),
                dense: true,
                contentPadding: EdgeInsets.only(left: it.parentId.isEmpty ? 0 : 24),
                controlAffinity: ListTileControlAffinity.leading,
                value: it.done,
                onChanged: (b) {
                  it.done = b ?? false;
                  if (it.done) {
                    c.timeline.add(TimelineEvent(text: 'Feito: ${it.description}'));
                  }
                  store.touch(c);
                },
                title: Text(it.description,
                    style: TextStyle(
                        decoration: it.done ? TextDecoration.lineThrough : null)),
                subtitle: Text([
                  opCode(it.op, it.labFlag, it.paintFlag,
                      removeInstall: it.removeInstall,
                      alsoRepair: it.alsoRepair),
                  opNames(it.op, it.labFlag, it.paintFlag,
                      removeInstall: it.removeInstall,
                      alsoRepair: it.alsoRepair),
                  if (byItem[it.id] != null)
                    'insumos: ${byItem[it.id]!.map((u) => '${u.name} ${num2(u.qty)} ${u.unit}').join(', ')}',
                  if (it.note.isNotEmpty) it.note,
                ].join(' · ')),
              ),
          ],
        ],
      ),
      SectionCard(
        title: 'Peças',
        icon: Icons.settings_outlined,
        children: [
          if (parts.isEmpty && clientParts.isEmpty)
            const Text('Nenhuma troca de peça.')
          else ...[
            for (final it in parts)
              () {
                final st = store.stockById(it.stockId);
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: st == null
                      ? const Icon(Icons.local_shipping_outlined)
                      : StockThumb(item: st, size: 40),
                  title: Text(it.description),
                  subtitle: Text(st == null
                      ? 'Peça nova${it.origin == PartOrigin.nenhuma ? '' : ' · ${it.origin.label}'}${it.supplier.isEmpty ? '' : ' · ${it.supplier}'}'
                      : 'Do estoque${st.address.isEmpty ? '' : ' · 📍 ${st.address}'}'),
                );
              }(),
            for (final s in clientParts)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: StockThumb(item: s, size: 40),
                title: Text(s.name),
                subtitle: Text(
                    'Peça do cliente guardada${s.address.isEmpty ? '' : ' · 📍 ${s.address}'}'),
              ),
          ],
        ],
      ),
      SectionCard(
        title: 'Insumos usados',
        icon: Icons.format_color_fill_outlined,
        trailing: TextButton.icon(
          onPressed: () => _issue(context, c),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Liberar insumo'),
        ),
        children: [
          if (c.supplies.isEmpty)
            const Text(
                'Lixa, massa, primer, verniz… Cada saída do estoque fica registrada aqui e entra no custo da O.S.')
          else
            for (final u in c.supplies)
              ListTile(
                key: ValueKey('supply-${u.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${u.name} · ${num2(u.qty)} ${u.unit}'),
                subtitle: Text([
                  date(u.date),
                  if (u.itemId.isNotEmpty && itemName(u.itemId).isNotEmpty)
                    'na peça ${itemName(u.itemId)}',
                  if (u.note.isNotEmpty) u.note,
                ].join(' · ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!production) Text(money(u.total)),
                  IconButton(
                    tooltip: 'Devolver ao estoque',
                    icon: const Icon(Icons.undo, size: 18),
                    onPressed: () async {
                      if (!await requireManager(context)) return;
                      store.returnSupply(c, u);
                    },
                  ),
                ]),
              ),
        ],
      ),
      SectionCard(
        title: 'Equipe',
        icon: Icons.engineering_outlined,
        children: [
          if (c.crew.isEmpty)
            const Text('Ninguém escalado (o gestor escala na aba Orçamento).')
          else
            for (final m in c.crew)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(store.contactById(m.contactId)?.name ?? '—'),
                subtitle: Text(m.role.worker),
              ),
        ],
      ),
      if (!c.reception.isEmpty || c.preDamages.isNotEmpty)
        SectionCard(
          title: 'Entrada do carro',
          icon: Icons.fact_check_outlined,
          children: [
            for (final l in receptionLines(c)) Text(l),
            if (c.preDamages.isNotEmpty)
              Text(
                  'Já tinha: ${c.preDamages.keys.map((k) => regionById(k)?.label ?? k).join(', ')}',
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
    ];

    return ListView(padding: const EdgeInsets.all(12), children: children);
  }

  /// Saída de insumo do estoque para esta O.S. (o gestor libera).
  Future<void> _issue(BuildContext context, Claim c) async {
    final store = StoreScope.read(context);
    final materials =
        store.stock.where((s) => s.kind == StockKind.material).toList();
    if (materials.isEmpty) {
      toast(context, 'Cadastre os insumos na aba Estoque primeiro.');
      return;
    }
    if (!await requireManager(context,
        reason: 'Só o gestor/almoxarife libera insumos.')) {
      return;
    }
    if (!context.mounted) return;
    var stockId = materials.first.id;
    var qty = 1.0;
    var itemId = '';
    var note = '';
    final ok = await showFormDialog<bool>(
      context: context,
      title: 'Liberar insumo',
      onSave: () {
        final s = store.stockById(stockId);
        if (s == null || qty <= 0) {
          toast(context, 'Escolha o insumo e a quantidade.');
          return null;
        }
        return true;
      },
      body: (ctx, setS) {
        final s = store.stockById(stockId)!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Picker<String>(
              label: 'Insumo',
              value: stockId,
              values: [for (final m in materials) m.id],
              labelOf: (id) {
                final m = store.stockById(id)!;
                return '${m.name} (${num2(m.qty)} ${m.unit})';
              },
              onChanged: (id) => setS(() => stockId = id),
            ),
            const SizedBox(height: 12),
            NumField(
              label: 'Quantidade (${s.unit})',
              value: qty,
              onChanged: (n) => setS(() => qty = n),
            ),
            if (qty > s.qty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Estoque tem só ${num2(s.qty)} ${s.unit} — vai ficar negativo.',
                    style: const TextStyle(color: Colors.orange)),
              ),
            const SizedBox(height: 12),
            Picker<String>(
              label: 'Usado na peça (opcional)',
              value: itemId,
              values: ['', ...c.items.where((i) => i.approved).map((i) => i.id)],
              labelOf: (id) => id.isEmpty
                  ? 'O carro todo'
                  : c.items.firstWhere((i) => i.id == id).description,
              onChanged: (id) => setS(() => itemId = id),
            ),
            const SizedBox(height: 12),
            BoundField(
              label: 'Para quem / observação',
              value: note,
              onChanged: (v) => note = v,
            ),
            if (!store.settings.productionMode && s.cost > 0) ...[
              const SizedBox(height: 8),
              KeyValue('Custo', money(s.cost * qty), bold: true),
            ],
          ],
        );
      },
    );
    if (ok != true) return;
    final s = store.stockById(stockId);
    if (s == null) return;
    store.issueSupply(c, s, qty, itemId: itemId, note: note.trim());
  }
}

/// Valor aprovado x custo real (só no modo gestor).
class _CostCard extends StatelessWidget {
  const _CostCard({required this.claim});
  final Claim claim;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final j = jobCost(claim, store.settings,
        entries: store.entries,
        contactById: store.contactById,
        stockById: store.stockById);
    final good = j.profit >= 0;
    final color = good ? Colors.green.shade700 : Colors.red.shade700;
    return SectionCard(
      title: 'Custo real da O.S.',
      icon: Icons.query_stats,
      children: [
        KeyValue('Valor aprovado (orçamento)', money(j.approved), bold: true),
        const Divider(height: 16),
        KeyValue('Equipe (pintor, funileiro…)', money(j.crew)),
        KeyValue('Insumos usados', money(j.supplies)),
        KeyValue('Peças do estoque (custo)', money(j.stockParts)),
        KeyValue('Outros gastos do carro (Financeiro)', money(j.otherExpenses)),
        KeyValue('Custo total', money(j.total), bold: true),
        const Divider(height: 16),
        KeyValue(good ? 'Lucro' : 'Prejuízo', money(j.profit),
            bold: true, color: color),
        Text('Margem ${pct(j.marginPct)}',
            style: t.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}
