import 'package:flutter/material.dart';

import '../calc.dart';
import '../format.dart';
import '../models.dart';
import '../seed.dart';
import '../theme.dart';
import 'widgets.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  String _q = '';
  ItemOp? _op;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final list = store.catalog
        .where((e) =>
            (_op == null || e.op == _op) &&
            (e.description.toLowerCase().contains(_q.toLowerCase()) ||
                e.partNumber.toLowerCase().contains(_q.toLowerCase())))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de peças e serviços')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final it = await _editCatalog(context, CatalogItem());
          if (it != null) store.upsertCatalog(it);
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por descrição ou código',
              ),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final op in ItemOp.values)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: FilterChip(
                      label: Text(op.label),
                      selected: _op == op,
                      showCheckmark: false,
                      onSelected: (b) => setState(() => _op = b ? op : null),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    text:
                        'Monte sua tabela de preços: peças, horas de reparo e pintura e serviços que você usa sempre.')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = list[i];
                      final value = itemValues(e.toBudgetItem(), s).total;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(e.op.code,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                        title: Text(e.description),
                        subtitle: Text([
                          e.op.label,
                          if (e.partNumber.isNotEmpty) e.partNumber,
                          if (e.price > 0) money(e.price),
                          if (e.laborHours > 0)
                            'MO ${num2(e.laborHours)} h ${e.laborType.label}',
                          if (e.paintHours > 0) 'pintura ${num2(e.paintHours)} h',
                        ].join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(money(value),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Excluir',
                              onPressed: () async {
                                if (await confirm(context, 'Excluir do catálogo?',
                                    e.description,
                                    ok: 'Excluir', danger: true)) {
                                  store.removeCatalog(e);
                                }
                              },
                            ),
                          ],
                        ),
                        onTap: () async {
                          final copy = CatalogItem.fromJson(e.toJson());
                          final r = await _editCatalog(context, copy);
                          if (r != null) {
                            final idx = store.catalog.indexOf(e);
                            if (idx >= 0) store.catalog[idx] = r;
                            store.upsertCatalog(r);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Future<CatalogItem?> _editCatalog(BuildContext context, CatalogItem it) {
  return showFormDialog<CatalogItem>(
    context: context,
    title: it.description.isEmpty ? 'Novo item do catálogo' : 'Editar item',
    onSave: () {
      if (it.description.trim().isEmpty) {
        toast(context, 'Informe a descrição.');
        return null;
      }
      it.description = it.description.trim();
      return it;
    },
    body: (ctx, setS) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ItemOp>(
          segments: [
            for (final op in ItemOp.values)
              ButtonSegment(value: op, label: Text(op.code), tooltip: op.label),
          ],
          selected: {it.op},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setS(() => it.op = s.first),
        ),
        const SizedBox(height: 4),
        Text(it.op.label, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        BoundField(
            label: 'Descrição',
            value: it.description,
            onChanged: (t) => it.description = t),
        const SizedBox(height: 12),
        BoundField(
            label: 'Código da peça (opcional)',
            value: it.partNumber,
            capitalization: TextCapitalization.characters,
            onChanged: (t) => it.partNumber = t),
        const SizedBox(height: 12),
        Picker<LaborType>(
          label: 'Tipo de mão de obra',
          value: it.laborType,
          values: LaborType.values,
          labelOf: (e) => e.label,
          onChanged: (e) => setS(() => it.laborType = e),
        ),
        const SizedBox(height: 12),
        if (it.op == ItemOp.troca || it.op == ItemOp.servico) ...[
          NumField(
              label: it.op == ItemOp.troca ? 'Preço da peça' : 'Valor do serviço',
              prefix: 'R\$',
              value: it.price,
              onChanged: (n) => it.price = n),
          const SizedBox(height: 12),
        ],
        NumField(
            label: 'Horas de mão de obra',
            suffix: 'h',
            value: it.laborHours,
            onChanged: (n) => it.laborHours = n),
        const SizedBox(height: 12),
        NumField(
            label: 'Horas de pintura',
            suffix: 'h',
            value: it.paintHours,
            onChanged: (n) => it.paintHours = n),
        const SizedBox(height: 12),
        Picker<String>(
          label: 'Região do carro (mapa de avarias)',
          value: it.region,
          values: ['', ...carRegions.map((r) => r.id)],
          labelOf: (id) =>
              id.isEmpty ? 'Nenhuma' : (regionById(id)?.label ?? id),
          onChanged: (v) => setS(() => it.region = v),
        ),
      ],
    ),
  );
}
