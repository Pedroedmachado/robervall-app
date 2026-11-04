import 'package:flutter/material.dart';

import '../format.dart';
import '../inspection.dart';
import '../theme.dart';
import 'widgets.dart';

/// Catálogo de serviços da Inspeção 3D: preço e tempo na gravidade leve;
/// moderada e grave sobem pelo fator da gravidade.
class InspectionServicesPage extends StatelessWidget {
  const InspectionServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final list = [...store.inspServices]
      ..sort((a, b) => '${a.category}${a.name}'.compareTo('${b.category}${b.name}'));
    return Scaffold(
      appBar: AppBar(title: const Text('Serviços da inspeção 3D')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final t = await editInspService(context, ServiceTemplate());
          if (t != null) store.upsertInspService(t);
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo serviço'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                'Valores da gravidade Leve. Moderada = ×${severities[2]!.$3} e Grave = ×${severities[3]!.$3} '
                '(nos serviços que acompanham a gravidade). São os serviços sugeridos ao registrar uma avaria.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          for (final t in list)
            Card(
              child: ListTile(
                title: Text(t.name),
                subtitle: Text([
                  t.category,
                  t.groups.isEmpty ? 'qualquer peça' : t.groups.map((g) => g.label).join(', '),
                  if (t.types.isNotEmpty) t.types.map(damageTypeLabel).join(', '),
                  if (t.minSeverity > 1) 'a partir de ${severityName(t.minSeverity).toLowerCase()}',
                ].join(' · ')),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(t.price), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(t.minutes == 0 ? '' : hoursText(t.minutes),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                onTap: () async {
                  final copy = ServiceTemplate.fromJson(t.toJson());
                  final r = await editInspService(context, copy, canDelete: true);
                  if (r == null) return;
                  if (r.id == '__delete__') {
                    store.removeInspService(t);
                    return;
                  }
                  final i = store.inspServices.indexOf(t);
                  store.inspServices[i] = r;
                  store.changed();
                },
              ),
            ),
        ],
      ),
    );
  }
}

Future<ServiceTemplate?> editInspService(BuildContext context, ServiceTemplate t,
    {bool canDelete = false}) {
  return showFormDialog<ServiceTemplate>(
    context: context,
    title: t.name.isEmpty ? 'Novo serviço da inspeção' : 'Editar serviço',
    onSave: () {
      if (t.name.trim().isEmpty) {
        toast(context, 'Informe o nome do serviço.');
        return null;
      }
      t.name = t.name.trim();
      return t;
    },
    body: (ctx, setS) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BoundField(label: 'Serviço', value: t.name, onChanged: (v) => t.name = v),
        const SizedBox(height: 12),
        Picker<String>(
          label: 'Categoria',
          value: serviceCategories.contains(t.category) ? t.category : serviceCategories.first,
          values: serviceCategories,
          labelOf: (e) => e,
          onChanged: (e) => setS(() => t.category = e),
        ),
        const SizedBox(height: 12),
        FieldGrid(maxColumns: 2, children: [
          NumField(
              label: 'Valor (gravidade leve)',
              prefix: 'R\$',
              value: t.price,
              onChanged: (v) => t.price = v),
          NumField(
              label: 'Tempo (minutos)',
              value: t.minutes.toDouble(),
              onChanged: (v) => t.minutes = v.round()),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Preço e tempo acompanham a gravidade'),
          value: t.followsSeverity,
          onChanged: (b) => setS(() => t.followsSeverity = b),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('É peça ou insumo'),
          subtitle: const Text('Entra em "Peças e insumos"; senão é mão de obra.'),
          value: t.isPart,
          onChanged: (b) => setS(() => t.isPart = b),
        ),
        const SizedBox(height: 8),
        Text('Aparece para', style: Theme.of(ctx).textTheme.labelLarge),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final g in PartGroup.values)
            FilterChip(
              label: Text(g.label),
              selected: t.groups.contains(g),
              onSelected: (b) => setS(() => b ? t.groups.add(g) : t.groups.remove(g)),
            ),
        ]),
        Text(t.groups.isEmpty ? 'Nenhum marcado = qualquer peça.' : '',
            style: Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text('Tipos de avaria', style: Theme.of(ctx).textTheme.labelLarge),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final (id, label) in damageTypes)
            FilterChip(
              label: Text(label),
              selected: t.types.contains(id),
              onSelected: (b) => setS(() => b ? t.types.add(id) : t.types.remove(id)),
            ),
        ]),
        Text(t.types.isEmpty ? 'Nenhum marcado = qualquer tipo.' : '',
            style: Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text('Aparece a partir da gravidade', style: Theme.of(ctx).textTheme.labelLarge),
        Wrap(spacing: 6, children: [
          for (final s in [1, 2, 3])
            ChoiceChip(
              label: Text(severityName(s)),
              selected: t.minSeverity == s,
              onSelected: (_) => setS(() => t.minSeverity = s),
            ),
        ]),
        if (canDelete) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, ServiceTemplate(id: '__delete__')),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir serviço'),
            ),
          ),
        ],
      ],
    ),
  );
}
