import 'package:flutter/material.dart';

import '../calc.dart';
import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'widgets.dart';

class BudgetTab extends StatelessWidget {
  const BudgetTab({super.key, required this.claim});
  final Claim claim;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final c = claim;
    final totals = computeTotals(c, s);

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () async {
            final it = await editBudgetItem(context, null);
            if (it != null) {
              c.items.add(it);
              store.touch(c);
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('Novo item'),
        ),
        FilledButton.tonalIcon(
          onPressed: () async {
            final picked = await pickFromCatalog(context, store);
            if (picked.isNotEmpty) {
              c.items.addAll(picked.map((e) => e.toBudgetItem()));
              store.touch(c);
            }
          },
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('Do catálogo'),
        ),
      ],
    );

    final itemsCard = SectionCard(
      title: 'Itens do orçamento',
      icon: Icons.list_alt,
      children: [
        actions,
        const SizedBox(height: 12),
        if (c.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Nenhum item. Adicione peças, reparos, pintura e serviços — ou marque as avarias no carro e gere os itens automaticamente.',
              textAlign: TextAlign.center,
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: c.items.length,
            onReorder: (a, b) {
              if (b > a) b--;
              final it = c.items.removeAt(a);
              c.items.insert(b, it);
              store.touch(c);
            },
            itemBuilder: (context, i) {
              final it = c.items[i];
              return _ItemRow(
                key: ValueKey(it.id),
                index: i,
                item: it,
                values: itemValues(it, s),
                onTap: () async {
                  final edited = await editBudgetItem(context, it);
                  if (edited != null) {
                    c.items[i] = edited;
                    store.touch(c);
                  }
                },
                onToggle: (v) {
                  it.approved = v;
                  store.touch(c);
                },
                onDelete: () {
                  c.items.removeAt(i);
                  store.touch(c);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                      content: Text('Item "${it.description}" removido'),
                      action: SnackBarAction(
                        label: 'Desfazer',
                        onPressed: () {
                          c.items.insert(i.clamp(0, c.items.length), it);
                          store.touch(c);
                        },
                      ),
                    ));
                },
              );
            },
          ),
      ],
    );

    final summary = SectionCard(
      title: 'Resumo',
      icon: Icons.calculate_outlined,
      children: [
        KeyValue('Peças', money(totals.parts)),
        KeyValue('Mão de obra (${num2(totals.laborHours)} h)', money(totals.labor)),
        KeyValue('Pintura (${num2(totals.paintHours)} h)', money(totals.paintLabor)),
        KeyValue('Material de pintura', money(totals.paintMaterial)),
        KeyValue('Serviços', money(totals.services)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: NumField(
              label: 'Outros custos (guincho…)',
              prefix: 'R\$',
              value: c.extraCosts,
              onChanged: (v) {
                c.extraCosts = v;
                store.touch(c);
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: NumField(
              label: 'Desconto',
              suffix: '%',
              value: c.discountPct,
              onChanged: (v) {
                c.discountPct = v.clamp(0, 100).toDouble();
                store.touch(c);
              },
            ),
          ),
        ]),
        const Divider(height: 24),
        KeyValue('Subtotal', money(totals.subtotal)),
        if (totals.discount > 0)
          KeyValue('Desconto', '- ${money(totals.discount)}',
              color: Colors.green.shade700),
        KeyValue('Total', money(totals.total), bold: true),
        if (c.type == ClaimType.seguradora || c.type == ClaimType.terceiro) ...[
          const Divider(height: 24),
          if (c.type == ClaimType.seguradora)
            KeyValue('Franquia (cliente)', money(totals.deductible)),
          KeyValue('Seguradora paga', money(totals.insurerPays), bold: true),
          KeyValue('Cliente paga', money(totals.customerPays)),
        ],
        if (totals.rejectedCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${totals.rejectedCount} item(ns) não aprovado(s) fora do total.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (c.vehicle.fipeValue > 0) ...[
          const Divider(height: 24),
          KeyValue('Valor FIPE', money(c.vehicle.fipeValue)),
          KeyValue('Orçamento / FIPE', pct(totals.fipePct),
              color: totals.possibleTotalLoss ? Colors.red : null,
              bold: totals.possibleTotalLoss),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (totals.fipePct / 100).clamp(0, 1).toDouble(),
              minHeight: 8,
              color: totals.possibleTotalLoss ? Colors.red : brandSeed,
            ),
          ),
          if (totals.possibleTotalLoss) ...[
            const SizedBox(height: 8),
            Text(
              'Atenção: o orçamento passou de ${num2(s.totalLossPct)}% do valor FIPE. Pode ser caso de perda total (indenização integral).',
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ],
    );

    return LayoutBuilder(builder: (context, cons) {
      if (cons.maxWidth >= 1000) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: itemsCard),
              const SizedBox(width: 16),
              SizedBox(width: 340, child: summary),
            ],
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [itemsCard, summary],
      );
    });
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.index,
    required this.item,
    required this.values,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });
  final int index;
  final BudgetItem item;
  final ItemValues values;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  Color _opColor(ItemOp op) {
    switch (op) {
      case ItemOp.troca:
        return const Color(0xFF1E88E5);
      case ItemOp.reparo:
        return const Color(0xFFFB8C00);
      case ItemOp.pintura:
        return const Color(0xFF8E24AA);
      case ItemOp.servico:
        return const Color(0xFF00897B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final it = item;
    final details = <String>[
      if (it.op == ItemOp.troca)
        '${num2(it.qty)} × ${money(it.price)}${it.origin == PartOrigin.nenhuma ? '' : ' · ${it.origin.label}'}',
      if (it.op == ItemOp.servico) money(it.price * (it.qty <= 0 ? 1 : it.qty)),
      if (it.laborHours > 0) 'MO ${num2(it.laborHours)} h (${it.laborType.label})',
      if (it.paintHours > 0) 'Pintura ${num2(it.paintHours)} h',
      if (it.discountPct > 0) 'desc. ${num2(it.discountPct)}%',
      if (it.supplier.isNotEmpty) it.supplier,
    ];
    final color = _opColor(it.op);
    return Opacity(
      opacity: it.approved ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border.all(color: t.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.drag_indicator, size: 18),
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(it.op.code,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.description.isEmpty ? '(sem descrição)' : it.description,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration:
                              it.approved ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      if (details.isNotEmpty)
                        Text(details.join(' · '),
                            style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(money(values.total),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Tooltip(
                  message: it.approved ? 'Aprovado' : 'Não aprovado',
                  child: Checkbox(
                    value: it.approved,
                    onChanged: (v) => onToggle(v ?? true),
                  ),
                ),
                IconButton(
                  tooltip: 'Remover',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre o editor de item. Retorna uma cópia editada (ou novo item).
Future<BudgetItem?> editBudgetItem(BuildContext context, BudgetItem? original) {
  final wide = isWide(context);
  final editor = _ItemEditor(original: original);
  if (wide) {
    return showDialog<BudgetItem>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(width: 640, height: 720, child: editor),
      ),
    );
  }
  return Navigator.of(context).push<BudgetItem>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => editor));
}

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({this.original});
  final BudgetItem? original;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final BudgetItem it = widget.original == null
      ? BudgetItem()
      : (BudgetItem.fromJson(widget.original!.toJson()));
  bool _saveToCatalog = false;

  void _fillFromCatalog(CatalogItem ci) {
    setState(() {
      it.description = ci.description;
      it.partNumber = ci.partNumber;
      it.op = ci.op;
      it.laborType = ci.laborType;
      it.price = ci.price;
      it.laborHours = ci.laborHours;
      it.paintHours = ci.paintHours;
      if (ci.region.isNotEmpty) it.region = ci.region;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final v = itemValues(it, s);
    final isNew = widget.original == null;
    final priceLabel = it.op == ItemOp.servico ? 'Valor do serviço' : 'Preço unitário da peça';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text(isNew ? 'Novo item' : 'Editar item'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: () {
                if (it.description.trim().isEmpty) {
                  toast(context, 'Informe a descrição do item.');
                  return;
                }
                if (_saveToCatalog) {
                  store.upsertCatalog(CatalogItem(
                    description: it.description.trim(),
                    partNumber: it.partNumber,
                    op: it.op,
                    laborType: it.laborType,
                    price: it.price,
                    laborHours: it.laborHours,
                    paintHours: it.paintHours,
                    region: it.region,
                  ));
                }
                Navigator.pop(context, it);
              },
              child: const Text('Salvar'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<ItemOp>(
            segments: [
              for (final op in ItemOp.values)
                ButtonSegment(value: op, label: Text(op.label)),
            ],
            selected: {it.op},
            showSelectedIcon: false,
            onSelectionChanged: (sel) => setState(() => it.op = sel.first),
          ),
          const SizedBox(height: 16),
          _CatalogAutocomplete(
            initial: it.description,
            catalog: store.catalog,
            onText: (t) => it.description = t,
            onPick: _fillFromCatalog,
          ),
          const SizedBox(height: 12),
          FieldGrid(maxColumns: 2, children: [
            if (it.op == ItemOp.troca)
              BoundField(
                label: 'Código da peça',
                value: it.partNumber,
                capitalization: TextCapitalization.characters,
                onChanged: (t) => it.partNumber = t,
              ),
            if (it.op == ItemOp.troca)
              Picker<PartOrigin>(
                label: 'Origem da peça',
                value: it.origin,
                values: PartOrigin.values,
                labelOf: (e) => e.label,
                onChanged: (e) => setState(() => it.origin = e),
              ),
            if (it.op == ItemOp.troca || it.op == ItemOp.servico)
              NumField(
                label: 'Quantidade',
                value: it.qty,
                onChanged: (n) => setState(() => it.qty = n <= 0 ? 1 : n),
              ),
            if (it.op == ItemOp.troca || it.op == ItemOp.servico)
              NumField(
                label: priceLabel,
                prefix: 'R\$',
                value: it.price,
                onChanged: (n) => setState(() => it.price = n),
              ),
            Picker<LaborType>(
              label: 'Tipo de mão de obra',
              value: it.laborType,
              values: LaborType.values,
              labelOf: (e) => '${e.label} (${money(s.rateFor(e))}/h)',
              onChanged: (e) => setState(() => it.laborType = e),
            ),
            NumField(
              label: it.op == ItemOp.reparo
                  ? 'Horas de reparo'
                  : 'Horas de mão de obra (R&I)',
              suffix: 'h',
              value: it.laborHours,
              onChanged: (n) => setState(() => it.laborHours = n),
            ),
            NumField(
              label: 'Horas de pintura',
              suffix: 'h',
              value: it.paintHours,
              onChanged: (n) => setState(() => it.paintHours = n),
            ),
            if (it.op == ItemOp.troca || it.op == ItemOp.servico)
              NumField(
                label: 'Desconto no item',
                suffix: '%',
                value: it.discountPct,
                onChanged: (n) =>
                    setState(() => it.discountPct = n.clamp(0, 100).toDouble()),
              ),
            if (it.op == ItemOp.troca)
              BoundField(
                label: 'Fornecedor',
                value: it.supplier,
                capitalization: TextCapitalization.words,
                suggestions: [
                  for (final c in store.contactsOf(ContactKind.fornecedor)) c.name
                ],
                onChanged: (t) => it.supplier = t,
              ),
          ]),
          const SizedBox(height: 12),
          BoundField(
            label: 'Observação',
            value: it.note,
            maxLines: 3,
            onChanged: (t) => it.note = t,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Item aprovado'),
            subtitle: const Text('Itens não aprovados ficam fora do total'),
            value: it.approved,
            onChanged: (b) => setState(() => it.approved = b),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Salvar também no catálogo'),
            value: _saveToCatalog,
            onChanged: (b) => setState(() => _saveToCatalog = b ?? false),
          ),
          const Divider(height: 24),
          if (v.parts > 0) KeyValue('Peças', money(v.parts)),
          if (v.services > 0) KeyValue('Serviço', money(v.services)),
          if (v.labor > 0) KeyValue('Mão de obra', money(v.labor)),
          if (v.paintLabor > 0) KeyValue('Pintura', money(v.paintLabor)),
          if (v.paintMaterial > 0)
            KeyValue('Material de pintura', money(v.paintMaterial)),
          KeyValue('Total do item', money(v.total), bold: true),
        ],
      ),
    );
  }
}

class _CatalogAutocomplete extends StatelessWidget {
  const _CatalogAutocomplete({
    required this.initial,
    required this.catalog,
    required this.onText,
    required this.onPick,
  });
  final String initial;
  final List<CatalogItem> catalog;
  final ValueChanged<String> onText;
  final ValueChanged<CatalogItem> onPick;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<CatalogItem>(
      initialValue: TextEditingValue(text: initial),
      displayStringForOption: (o) => o.description,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<CatalogItem>.empty();
        return catalog
            .where((e) => e.description.toLowerCase().contains(q))
            .take(10);
      },
      onSelected: (o) {
        onText(o.description);
        onPick(o);
      },
      fieldViewBuilder: (context, ctl, focus, onSubmit) => TextField(
        controller: ctl,
        focusNode: focus,
        autofocus: initial.isEmpty,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Descrição (peça ou serviço)',
          hintText: 'Digite para buscar no catálogo',
          prefixIcon: Icon(Icons.search, size: 20),
        ),
        onChanged: onText,
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300, maxWidth: 520),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final o in options)
                  ListTile(
                    dense: true,
                    leading: Text(o.op.code,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    title: Text(o.description),
                    subtitle: Text([
                      if (o.price > 0) money(o.price),
                      if (o.laborHours > 0) 'MO ${num2(o.laborHours)} h',
                      if (o.paintHours > 0) 'pint. ${num2(o.paintHours)} h',
                    ].join(' · ')),
                    onTap: () => onSelected(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Seleção múltipla de itens do catálogo.
Future<List<CatalogItem>> pickFromCatalog(
    BuildContext context, AppStore store) async {
  final selected = <CatalogItem>{};
  String q = '';
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final list = store.catalog
            .where((e) => e.description.toLowerCase().contains(q.toLowerCase()))
            .toList();
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar no catálogo'),
                  onChanged: (v) => setS(() => q = v),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const EmptyState(
                        icon: Icons.inventory_2_outlined,
                        text: 'Nada no catálogo com esse nome.')
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final e = list[i];
                          return CheckboxListTile(
                            value: selected.contains(e),
                            onChanged: (b) => setS(() =>
                                b == true ? selected.add(e) : selected.remove(e)),
                            title: Text(e.description),
                            subtitle: Text([
                              e.op.label,
                              if (e.price > 0) money(e.price),
                              if (e.laborHours > 0) 'MO ${num2(e.laborHours)} h',
                              if (e.paintHours > 0)
                                'pintura ${num2(e.paintHours)} h',
                            ].join(' · ')),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(ctx, true),
                      child: Text('Adicionar ${selected.length} item(ns)'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  return r == true ? selected.toList() : <CatalogItem>[];
}
