import 'package:flutter/material.dart';

import '../calc.dart';
import '../complements.dart';
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
              if (context.mounted) await offerComplements(context, c, it);
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
        if (c.items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Toque num item para editar · caixa marca aprovado · arraste pela alça para reordenar',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
        if (c.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Nenhum item. Adicione as peças (troca, reparo, pintura) e os serviços — ou marque as avarias no carro e gere as peças automaticamente.',
              textAlign: TextAlign.center,
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: c.items.length,
            // ignore: deprecated_member_use
            onReorder: (a, b) {
              if (b > a) b--;
              final it = c.items.removeAt(a);
              c.items.insert(b, it);
              // complementos acompanham a peça principal
              c.items = groupChildren(c.items);
              store.touch(c);
            },
            itemBuilder: (context, i) {
              final it = c.items[i];
              return _ItemRow(
                key: ValueKey(it.id),
                index: i,
                item: it,
                values: itemValues(it, s),
                hasComplements: complementsFor(it).isNotEmpty,
                onComplements: () => offerComplements(context, c, it,
                    alwaysShow: true),
                onTap: () async {
                  final edited = await editBudgetItem(context, it);
                  if (edited != null) {
                    final becameReplace = it.op != ItemOp.troca &&
                        edited.op == ItemOp.troca;
                    c.items[i] = edited;
                    store.touch(c);
                    if (becameReplace && context.mounted) {
                      await offerComplements(context, c, edited);
                    }
                  }
                },
                onToggle: (v) {
                  it.approved = v;
                  store.touch(c);
                },
                onDelete: () {
                  // apagar a peça principal leva junto os complementos
                  final before = List<BudgetItem>.of(c.items);
                  final kids = childrenOf(c.items, it);
                  c.items.remove(it);
                  c.items.removeWhere(kids.contains);
                  store.touch(c);
                  showUndo(
                      context,
                      kids.isEmpty
                          ? '"${it.description}" removido'
                          : '"${it.description}" e ${kids.length} complementos removidos',
                      () {
                    c.items = before;
                    store.touch(c);
                  });
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
    this.hasComplements = false,
    this.onComplements,
  });
  final bool hasComplements;
  final VoidCallback? onComplements;
  final int index;
  final BudgetItem item;
  final ItemValues values;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final it = item;
    final qty = it.qty <= 0 ? 1.0 : it.qty;
    final extra = <String>[
      if (it.op == ItemOp.troca)
        '${qty == 1 ? '' : '${num2(qty)} × '}${money(it.price)}',
      if (it.op == ItemOp.servico) money(it.price * qty),
      if (it.op == ItemOp.troca && it.origin != PartOrigin.nenhuma)
        it.origin.label,
      if (it.discountPct > 0) 'desconto ${num2(it.discountPct)}%',
      if (it.supplier.isNotEmpty) it.supplier,
    ];
    final child = it.parentId.isNotEmpty;
    return Opacity(
      opacity: it.approved ? 1 : 0.5,
      child: Container(
        margin: EdgeInsets.only(bottom: 6, left: child ? 28 : 0),
        decoration: BoxDecoration(
          border: Border.all(color: t.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.drag_indicator, size: 18),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (child)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.subdirectory_arrow_right,
                                size: 16, color: t.colorScheme.outline),
                          ),
                        Expanded(
                          child: Text(
                            it.description.isEmpty
                                ? '(sem descrição)'
                                : it.description,
                            style: TextStyle(
                              fontWeight:
                                  child ? FontWeight.w500 : FontWeight.w600,
                              decoration: it.approved
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final d in opDetails(
                              it.op, it.laborHours, it.paintHours,
                              removeInstall: it.removeInstall))
                            OpChip(d),
                        ],
                      ),
                      if (extra.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(extra.join(' · '),
                            style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(money(values.total),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: it.approved ? 'Aprovado' : 'Não aprovado',
                          child: Checkbox(
                            value: it.approved,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged: (v) => onToggle(v ?? true),
                          ),
                        ),
                        if (hasComplements)
                          IconButton(
                            tooltip: 'Peças complementares',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.account_tree_outlined,
                                size: 20),
                            onPressed: onComplements,
                          ),
                        IconButton(
                          tooltip: 'Remover',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: onDelete,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Etiqueta de operação escrita por extenso ("Troca", "Pintura 2 h").
class OpChip extends StatelessWidget {
  const OpChip(this.text, {super.key});
  final String text;

  Color get _color {
    if (text.startsWith('Troca')) return const Color(0xFF1E88E5);
    if (text.startsWith('Pintura')) return const Color(0xFF8E24AA);
    if (text.startsWith('Serviço')) return const Color(0xFF00897B);
    return const Color(0xFFEF6C00); // reparo / mão de obra
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              color: c, fontSize: 12, fontWeight: FontWeight.w600)),
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
      ? BudgetItem(op: ItemOp.reparo)
      : (BudgetItem.fromJson(widget.original!.toJson()));
  late bool _service = it.op == ItemOp.servico;
  late bool _replace = it.op == ItemOp.troca;
  bool _saveToCatalog = false;

  void _fillFromCatalog(CatalogItem ci) {
    setState(() {
      it.description = ci.description;
      it.partNumber = ci.partNumber;
      it.laborType = ci.laborType;
      it.price = ci.price;
      it.laborHours = ci.laborHours;
      it.paintHours = ci.paintHours;
      _service = ci.op == ItemOp.servico;
      _replace = ci.op == ItemOp.troca;
      it.removeInstall = ci.removeInstall;
      if (ci.region.isNotEmpty) it.region = ci.region;
    });
  }

  void _applyOp() {
    if (_service || _replace) it.removeInstall = false;
    if (_service) {
      it.laborHours = 0;
      it.paintHours = 0;
    }
    it.op = opFor(
        service: _service,
        replace: _replace,
        laborHours: it.laborHours,
        paintHours: it.paintHours);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    _applyOp();
    final v = itemValues(it, s);
    final isNew = widget.original == null;
    final showPrice = _service || _replace;

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
                _applyOp();
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
                    removeInstall: it.removeInstall,
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
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  label: Text('Peça'),
                  icon: Icon(Icons.car_repair)),
              ButtonSegment(
                  value: true,
                  label: Text('Serviço'),
                  icon: Icon(Icons.handyman_outlined)),
            ],
            selected: {_service},
            onSelectionChanged: (sel) => setState(() => _service = sel.first),
          ),
          const SizedBox(height: 16),
          _CatalogAutocomplete(
            initial: it.description,
            catalog: store.catalog,
            label: _service ? 'Serviço' : 'Peça',
            onText: (t) => it.description = t,
            onPick: _fillFromCatalog,
          ),
          if (!_service) ...[
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Trocar a peça'),
              subtitle: Text(_replace
                  ? 'Peça nova: informe o preço'
                  : 'Desligado: só reparo e/ou pintura da peça atual'),
              value: _replace,
              onChanged: (b) => setState(() => _replace = b),
            ),
            if (!_replace) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, children: [
                ChoiceChip(
                  label: const Text('Reparo (R)'),
                  selected: !it.removeInstall,
                  onSelected: (_) => setState(() => it.removeInstall = false),
                ),
                ChoiceChip(
                  label: const Text('Remoção e instalação (R&I)'),
                  selected: it.removeInstall,
                  onSelected: (_) => setState(() => it.removeInstall = true),
                ),
              ]),
            ],
          ],
          const SizedBox(height: 8),
          FieldGrid(maxColumns: 2, children: [
            if (showPrice)
              NumField(
                label: _service ? 'Valor do serviço' : 'Preço unitário da peça',
                prefix: 'R\$',
                value: it.price,
                onChanged: (n) => setState(() => it.price = n),
              ),
            if (showPrice)
              NumField(
                label: 'Quantidade',
                value: it.qty,
                onChanged: (n) => setState(() => it.qty = n <= 0 ? 1 : n),
              ),
            if (!_service)
              NumField(
                label: _replace
                    ? 'Horas de mão de obra (tirar e colocar)'
                    : (it.removeInstall
                        ? 'Horas de remoção e instalação'
                        : 'Horas de reparo'),
                suffix: 'h',
                value: it.laborHours,
                onChanged: (n) => setState(() => it.laborHours = n),
              ),
            if (!_service)
              NumField(
                label: 'Horas de pintura',
                suffix: 'h',
                value: it.paintHours,
                onChanged: (n) => setState(() => it.paintHours = n),
              ),
            if (!_service)
              Picker<LaborType>(
                label: 'Tipo de mão de obra',
                value: it.laborType,
                values: LaborType.values,
                labelOf: (e) => '${e.label} (${money(s.rateFor(e))}/h)',
                onChanged: (e) => setState(() => it.laborType = e),
              ),
            if (_replace && !_service)
              Picker<PartOrigin>(
                label: 'Origem da peça',
                value: it.origin,
                values: PartOrigin.values,
                labelOf: (e) => e.label,
                onChanged: (e) => setState(() => it.origin = e),
              ),
            if (_replace && !_service)
              BoundField(
                label: 'Código da peça',
                value: it.partNumber,
                capitalization: TextCapitalization.characters,
                onChanged: (t) => it.partNumber = t,
              ),
            if (_replace && !_service)
              BoundField(
                label: 'Fornecedor',
                value: it.supplier,
                capitalization: TextCapitalization.words,
                suggestions: [
                  for (final c in store.contactsOf(ContactKind.fornecedor)) c.name
                ],
                onChanged: (t) => it.supplier = t,
              ),
            if (showPrice)
              NumField(
                label: 'Desconto no item',
                suffix: '%',
                value: it.discountPct,
                onChanged: (n) =>
                    setState(() => it.discountPct = n.clamp(0, 100).toDouble()),
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
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final d in opDetails(it.op, it.laborHours, it.paintHours, removeInstall: it.removeInstall))
              OpChip(d),
          ]),
          const SizedBox(height: 8),
          if (v.parts > 0) KeyValue('Peça', money(v.parts)),
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
    this.label = 'Peça',
  });
  final String initial;
  final String label;
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
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Digite o nome ou busque no catálogo',
          prefixIcon: const Icon(Icons.search, size: 20),
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
                    title: Text(o.description),
                    subtitle: Text([
                      ...opDetails(o.op, o.laborHours, o.paintHours, removeInstall: o.removeInstall),
                      if (o.price > 0) money(o.price),
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
                              ...opDetails(e.op, e.laborHours, e.paintHours, removeInstall: e.removeInstall),
                              if (e.price > 0) money(e.price),
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


/// Mostra os complementos da peça (vidro, máquina, forro, chicote...) para
/// adicionar junto. Com [alwaysShow], abre mesmo se já estiverem lançados.
Future<void> offerComplements(BuildContext context, Claim c, BudgetItem parent,
    {bool alwaysShow = false}) async {
  final store = StoreScope.read(context);
  final existing = {
    for (final k in childrenOf(c.items, parent)) k.description.toLowerCase()
  };
  final options = [
    for (final (comp, on) in complementsFor(parent))
      if (!existing.contains(comp.name.toLowerCase())) (comp, on)
  ];
  if (options.isEmpty) {
    if (alwaysShow && context.mounted) {
      toast(context, 'Todos os complementos desta peça já estão no orçamento.');
    }
    return;
  }
  // sozinha, só abre quando há algo que normalmente vai junto
  if (!alwaysShow && !options.any((o) => o.$2)) return;
  final selected = <Complement>{
    for (final (comp, on) in options)
      if (on) comp
  };
  final s = store.settings;
  final picked = await showModalBottomSheet<List<Complement>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text('Peças complementares',
                    style: Theme.of(ctx).textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  parent.op == ItemOp.troca
                      ? 'Na troca de "${parent.description}" também entram:'
                      : 'Para reparar/pintar "${parent.description}" normalmente sai:',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (comp, _) in options)
                      CheckboxListTile(
                        dense: true,
                        value: selected.contains(comp),
                        onChanged: (b) => setS(() {
                          if (b == true) {
                            selected.add(comp);
                          } else {
                            selected.remove(comp);
                          }
                        }),
                        title: Text(comp.name),
                        subtitle: Text(comp.removeInstall
                            ? 'R&I · ${num2(comp.hours)} h · ${comp.laborType.label} · ${money(comp.hours * s.rateFor(comp.laborType))}'
                            : 'Troca · informe o preço depois'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setS(() {
                        if (selected.length == options.length) {
                          selected.clear();
                        } else {
                          selected
                            ..clear()
                            ..addAll(options.map((o) => o.$1));
                        }
                      }),
                      child: Text(selected.length == options.length
                          ? 'Desmarcar todos'
                          : 'Marcar todos'),
                    ),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Agora não')),
                    FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(ctx, [
                                for (final (comp, _) in options)
                                  if (selected.contains(comp)) comp
                              ]),
                      child: Text('Adicionar ${selected.length}'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (picked == null || picked.isEmpty) return;
  addComplements(c, parent, picked);
  store.touch(c);
}

/// Insere os complementos logo abaixo da peça principal.
void addComplements(Claim c, BudgetItem parent, List<Complement> comps) {
  final items = [for (final comp in comps) comp.toItem(parent.id)];
  final idx = c.items.indexOf(parent);
  final after = idx < 0 ? c.items.length : idx + 1 + childrenOf(c.items, parent).length;
  c.items.insertAll(after.clamp(0, c.items.length), items);
  c.items = groupChildren(c.items);
}
