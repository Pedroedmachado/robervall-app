import 'package:flutter/material.dart';

import '../car3d.dart';
import '../format.dart';
import '../inspection.dart';
import '../models.dart';
import '../modules.dart';
import '../store.dart';
import '../theme.dart';
import 'quote_preview_page.dart';
import 'widgets.dart';

/// Inspeção 3D: gira o carro, clica na peça, registra a avaria com tipo,
/// gravidade e serviços (preço e tempo pela gravidade) e tudo vai para o
/// orçamento.
class InspectionTab extends StatefulWidget {
  const InspectionTab({super.key, required this.claim});
  final Claim claim;

  @override
  State<InspectionTab> createState() => _InspectionTabState();
}

enum _Mode { summary, part, form }

class _InspectionTabState extends State<InspectionTab> {
  final _viewer = GlobalKey<Car3DViewState>();
  _Mode _mode = _Mode.summary;
  String? _part;

  // rascunho da avaria
  InspectionDamage? _editing;
  String _type = 'amassado';
  int _sev = 1;
  bool _noDamage = false;
  final Set<String> _chosen = {}; // ids dos serviços do catálogo
  final List<InspectionService> _manual = [];

  Claim get c => widget.claim;

  void _openPart(String id) => setState(() {
        _part = id;
        _mode = _Mode.part;
      });

  void _startForm({InspectionDamage? edit, bool noDamage = false}) {
    final store = StoreScope.read(context);
    setState(() {
      _editing = edit;
      _noDamage = edit != null ? edit.type.isEmpty : noDamage;
      _type = edit?.type.isNotEmpty == true ? edit!.type : 'amassado';
      _sev = edit?.severity ?? 1;
      _chosen.clear();
      _manual.clear();
      if (edit != null) {
        for (final s in edit.services) {
          final t = store.inspServices.where((t) => t.name == s.name).firstOrNull;
          if (t != null) {
            _chosen.add(t.id);
          } else {
            _manual.add(InspectionService(
                name: s.name, price: s.price, minutes: s.minutes, isPart: s.isPart));
          }
        }
      }
      _mode = _Mode.form;
    });
  }

  List<InspectionService> _draftServices(AppStore store) => [
        for (final t in store.inspServices)
          if (_chosen.contains(t.id)) t.forSeverity(_noDamage ? 1 : _sev),
        ..._manual,
      ];

  void _save(AppStore store, CarBody body) {
    final services = _draftServices(store);
    if (services.isEmpty) {
      toast(context, 'Escolha pelo menos um serviço.');
      return;
    }
    final d = _editing ?? InspectionDamage(partId: _part!);
    d
      ..type = _noDamage ? '' : _type
      ..severity = _noDamage ? 1 : _sev
      ..services = services;
    store.saveInspection(c, d);
    final label = partById(body, d.partId)?.label ?? d.partId;
    toast(context, '✓ $label registrada no orçamento.');
    setState(() {
      _mode = _Mode.summary;
      _part = null;
      _editing = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final body = CarBody.of(c.vehicle);
    final colors = <String, Color>{};
    final pins = <String, int>{};
    for (var i = 0; i < c.inspection.length; i++) {
      final d = c.inspection[i];
      final col = d.type.isEmpty ? const Color(0xFF2BB3A3) : severityColors[d.severity]!;
      final prev = c.inspection
          .where((e) => e.partId == d.partId && e != d && e.type.isNotEmpty)
          .fold(0, (a, e) => e.severity > a ? e.severity : a);
      colors[d.partId] = prev > d.severity && d.type.isNotEmpty ? severityColors[prev]! : col;
      pins.putIfAbsent(d.partId, () => i + 1);
    }

    final viewer = _viewerCard(context, store, body, colors, pins);
    final panel = _panel(context, store, body);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 900) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(12), child: viewer)),
          SizedBox(
            width: 390,
            child: ListView(padding: const EdgeInsets.fromLTRB(0, 12, 12, 24), children: [panel]),
          ),
        ]);
      }
      return ListView(
        key: const ValueKey('inspecao-lista'),
        padding: const EdgeInsets.all(12),
        children: [SizedBox(height: 430, child: viewer), const SizedBox(height: 12), panel],
      );
    });
  }

  Widget _viewerCard(BuildContext context, AppStore store, CarBody body,
      Map<String, Color> colors, Map<String, int> pins) {
    final t = Theme.of(context);
    Widget view(IconData icon, String tip, Camera3D cam) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 20, color: Colors.white70),
          onPressed: () => _viewer.currentState?.setView(cam),
        );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.1,
          colors: [Color(0xFF1A2A48), Color(0xFF0A1020)],
        ),
        border: Border.all(color: const Color(0x333D8BFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 0),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.vehicle.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                Text(
                    [
                      if (c.vehicle.plate.isNotEmpty) c.vehicle.plate,
                      if (c.vehicle.color.isNotEmpty) c.vehicle.color,
                      'Modelo 3D · ${body.label}',
                    ].join(' · '),
                    style: const TextStyle(color: Color(0xFF9FB3C8), fontSize: 12)),
              ]),
            ),
            PopupMenuButton<CarBody>(
              key: const ValueKey('carroceria'),
              tooltip: 'Carroceria do modelo 3D',
              initialValue: body,
              onSelected: (b) {
                c.vehicle.body = b.name;
                store.touch(c);
              },
              itemBuilder: (_) => [
                for (final b in CarBody.values)
                  PopupMenuItem(value: b, child: Text(b.label)),
              ],
              child: Chip(
                avatar: const Icon(Icons.directions_car_outlined, size: 16),
                label: Text(body.label),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ]),
        ),
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: Car3DView(
                key: _viewer,
                body: body,
                partColors: colors,
                pins: pins,
                selected: _part,
                onPart: _openPart,
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              bottom: 4,
              child: SingleChildScrollView(
                child: Column(children: [
                  view(Icons.threed_rotation, 'Vista 3/4', Camera3D.frontLeft),
                  view(Icons.arrow_upward, 'Frente', Camera3D.front),
                  view(Icons.arrow_back, 'Lado esquerdo', Camera3D.left),
                  view(Icons.arrow_forward, 'Lado direito', Camera3D.right),
                  view(Icons.arrow_downward, 'Traseira', Camera3D.back),
                  view(Icons.vertical_align_top, 'De cima', Camera3D.top),
                ]),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Row(children: [
            for (final s in [1, 2, 3]) ...[
              Icon(Icons.circle, size: 10, color: severityColors[s]),
              const SizedBox(width: 4),
              Text(severityName(s),
                  style: t.textTheme.bodySmall?.copyWith(color: Colors.white70)),
              const SizedBox(width: 12),
            ],
            const Spacer(),
            Flexible(
              child: Text('Arraste para girar · role para aproximar · toque numa peça',
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  style: t.textTheme.bodySmall?.copyWith(color: Colors.white54, fontSize: 11)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _panel(BuildContext context, AppStore store, CarBody body) => switch (_mode) {
        _Mode.summary => _summary(context, store, body),
        _Mode.part => _partCard(context, store, body),
        _Mode.form => _form(context, store, body),
      };

  Widget _summary(BuildContext context, AppStore store, CarBody body) {
    final t = Theme.of(context);
    final sum = summarize(c);
    final parts = partsFor(body);
    return SectionCard(
      title: 'Resumo da inspeção',
      icon: Icons.fact_check_outlined,
      children: [
        Text('Atendimento ${c.number} · ${date(c.createdAt)}',
            style: t.textTheme.bodySmall),
        const SizedBox(height: 8),
        if (c.customerName.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
                child: Text(c.customerName.trim().split(RegExp(r'\s+')).take(2).map((e) => e[0]).join().toUpperCase())),
            title: Text(c.customerName),
            subtitle: c.customerPhone.isEmpty ? null : Text(c.customerPhone),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            KeyValue('Total da inspeção', money(sum.total), bold: true),
            KeyValue('Prazo estimado',
                sum.days == 0 ? '—' : '${sum.days} ${sum.days == 1 ? 'dia útil' : 'dias úteis'}'),
            KeyValue('Tempo de serviço', sum.minutes == 0 ? '—' : hoursText(sum.minutes)),
          ]),
        ),
        const SizedBox(height: 12),
        Text('Avarias registradas (${c.inspection.length})',
            style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (c.inspection.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nenhuma ainda. Toque numa peça do carro para registrar.'),
          ),
        for (var i = 0; i < c.inspection.length; i++)
          () {
            final d = c.inspection[i];
            return ListTile(
              key: ValueKey('avaria3d-${d.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(
                radius: 13,
                backgroundColor:
                    d.type.isEmpty ? const Color(0xFF2BB3A3) : severityColors[d.severity],
                child: Text('${i + 1}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              title: Text(partById(body, d.partId)?.label ?? partLabel(d.partId)),
              subtitle: Text(d.type.isEmpty
                  ? 'Serviço sem avaria'
                  : '${damageTypeLabel(d.type)} · ${severityName(d.severity).toLowerCase()}'),
              trailing: Text(money(d.total),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => _openPart(d.partId),
            );
          }(),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('escolher-peca'),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Selecionar peça pela lista'),
          items: [
            for (final p in parts) DropdownMenuItem(value: p.id, child: Text(p.label)),
          ],
          onChanged: (v) {
            if (v != null) _openPart(v);
          },
        ),
        const Divider(height: 24),
        KeyValue('Peças e insumos', money(sum.parts)),
        KeyValue('Mão de obra', money(sum.labor)),
        KeyValue('Total da inspeção', money(sum.total), bold: true),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => QuotePreviewPage(claimId: c.id))),
          icon: const Icon(Icons.description_outlined),
          label: const Text('Ver orçamento'),
        ),
      ],
    );
  }

  Widget _partCard(BuildContext context, AppStore store, CarBody body) {
    final t = Theme.of(context);
    final part = partById(body, _part!);
    final here = c.inspection.where((d) => d.partId == _part).toList();
    final canEdit = gate.can(Perm.orcamentoEditar);
    return SectionCard(
      title: 'Peça selecionada',
      icon: Icons.ads_click,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _mode = _Mode.summary;
              _part = null;
            }),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Resumo da inspeção'),
          ),
        ),
        Text(part?.label ?? partLabel(_part!),
            style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        if (part != null) Text(part.side, style: t.textTheme.bodySmall),
        const SizedBox(height: 10),
        if (here.isEmpty)
          Row(children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
            const SizedBox(width: 6),
            const Expanded(child: Text('Nenhuma avaria registrada nesta peça.')),
          ])
        else
          for (final d in here)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.circle,
                    color: d.type.isEmpty ? const Color(0xFF2BB3A3) : severityColors[d.severity]),
                title: Text(d.type.isEmpty
                    ? 'Serviço sem avaria'
                    : '${damageTypeLabel(d.type)} · ${severityName(d.severity).toLowerCase()}'),
                subtitle: Text(
                    '${d.services.map((s) => s.name).join(', ')}\n${money(d.total)} · ${hoursText(d.minutes)}'),
                isThreeLine: true,
                trailing: canEdit
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Editar avaria',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _startForm(edit: d),
                        ),
                        IconButton(
                          tooltip: 'Excluir avaria',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () {
                            final idx = c.inspection.indexOf(d);
                            final items = c.items.where((e) => e.inspectionId == d.id).toList();
                            store.removeInspection(c, d);
                            showUndo(context, 'Avaria excluída', () {
                              c.inspection.insert(idx.clamp(0, c.inspection.length), d);
                              c.items.addAll(items);
                              store.touch(c);
                            });
                          },
                        ),
                      ])
                    : null,
              ),
            ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: canEdit ? () => _startForm() : null,
          icon: const Icon(Icons.add),
          label: const Text('Registrar avaria'),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: canEdit ? () => _startForm(noDamage: true) : null,
          icon: const Icon(Icons.build_outlined),
          label: const Text('Adicionar serviço sem avaria'),
        ),
      ],
    );
  }

  Widget _form(BuildContext context, AppStore store, CarBody body) {
    final t = Theme.of(context);
    final part = partById(body, _part!) ?? CarPart(_part!, partLabel(_part!), PartGroup.lataria);
    final suggested = [
      for (final ts in store.inspServices)
        if (_chosen.contains(ts.id) ||
            ts.appliesTo(part, _noDamage ? '' : _type, _noDamage ? 1 : _sev))
          ts,
    ];
    final services = _draftServices(store);
    final total = services.fold(0.0, (a, s) => a + s.price);
    final minutes = services.fold(0, (a, s) => a + s.minutes);
    Widget step(String n, String label) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Row(children: [
            CircleAvatar(radius: 10, child: Text(n, style: const TextStyle(fontSize: 11))),
            const SizedBox(width: 8),
            Text(label, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        );
    return SectionCard(
      title: _noDamage ? 'Serviço sem avaria' : 'Registrar avaria',
      icon: Icons.report_outlined,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _mode = _Mode.part),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Voltar'),
          ),
        ),
        Text(part.label, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        if (!_noDamage) ...[
          step('1', 'Tipo de avaria'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (id, label) in damageTypes)
              ChoiceChip(
                key: ValueKey('tipo-$id'),
                label: Text(label),
                selected: _type == id,
                onSelected: (_) => setState(() => _type = id),
              ),
          ]),
          step('2', 'Gravidade'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in [1, 2, 3])
              ChoiceChip(
                key: ValueKey('gravidade-$s'),
                avatar: Icon(Icons.circle, size: 12, color: severityColors[s]),
                label: Text(severityName(s)),
                selected: _sev == s,
                onSelected: (_) => setState(() => _sev = s),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(severities[_sev]!.$2, style: t.textTheme.bodySmall),
          ),
        ],
        step(_noDamage ? '1' : '3', 'Serviços necessários'),
        Wrap(spacing: 4, children: [
          TextButton.icon(
            onPressed: () => _addManual(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Manual'),
          ),
          TextButton.icon(
            onPressed: () => _pickFromCatalog(context, store),
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Catálogo'),
          ),
        ]),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final ts in suggested)
            () {
              final v = ts.forSeverity(_noDamage ? 1 : _sev);
              return FilterChip(
                key: ValueKey('servico-${ts.name}'),
                label: Text('${ts.name} · ${money(v.price)}'),
                selected: _chosen.contains(ts.id),
                onSelected: (b) => setState(() => b ? _chosen.add(ts.id) : _chosen.remove(ts.id)),
              );
            }(),
          for (final m in _manual)
            InputChip(
              label: Text('${m.name} · ${money(m.price)}'),
              selected: true,
              onDeleted: () => setState(() => _manual.remove(m)),
            ),
        ]),
        if (suggested.isEmpty && _manual.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Nenhum serviço do catálogo para esta peça. Use "Manual" ou "Catálogo".'),
          ),
        const Divider(height: 24),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Valor estimado', style: t.textTheme.bodySmall),
              Text(money(total),
                  key: const ValueKey('valor-estimado'),
                  style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Tempo', style: t.textTheme.bodySmall),
            Text(minutes == 0 ? '—' : hoursText(minutes),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ]),
        const SizedBox(height: 10),
        OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.end,
          overflowSpacing: 6,
          children: [
          TextButton(
            onPressed: () => setState(() => _mode = _Mode.part),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: services.isEmpty ? null : () => _save(store, body),
            icon: const Icon(Icons.check),
            label: Text(_noDamage ? 'Salvar serviço' : 'Salvar avaria'),
          ),
        ]),
      ],
    );
  }

  Future<void> _addManual(BuildContext context) async {
    var name = '';
    var price = 0.0;
    var minutes = 0.0;
    var isPart = false;
    final ok = await showFormDialog<bool>(
      context: context,
      title: 'Serviço manual',
      onSave: () {
        if (name.trim().isEmpty) {
          toast(context, 'Informe o nome do serviço.');
          return null;
        }
        return true;
      },
      body: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, children: [
        BoundField(label: 'Serviço', value: name, onChanged: (v) => name = v),
        const SizedBox(height: 12),
        NumField(label: 'Valor', prefix: 'R\$', value: price, onChanged: (v) => price = v),
        const SizedBox(height: 12),
        NumField(label: 'Tempo (minutos)', value: minutes, onChanged: (v) => minutes = v),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('É peça ou insumo'),
          value: isPart,
          onChanged: (b) => setS(() => isPart = b),
        ),
      ]),
    );
    if (ok == true) {
      setState(() => _manual.add(InspectionService(
          name: name.trim(), price: price, minutes: minutes.round(), isPart: isPart)));
    }
  }

  Future<void> _pickFromCatalog(BuildContext context, AppStore store) async {
    final picked = await showModalBottomSheet<ServiceTemplate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: ListView(shrinkWrap: true, children: [
            const ListTile(title: Text('Catálogo da inspeção')),
            for (final ts in store.inspServices)
              ListTile(
                title: Text(ts.name),
                subtitle: Text('${ts.category} · ${money(ts.forSeverity(_sev).price)} · ${hoursText(ts.forSeverity(_sev).minutes)}'),
                onTap: () => Navigator.pop(ctx, ts),
              ),
          ]),
        ),
      ),
    );
    if (picked != null) setState(() => _chosen.add(picked.id));
  }
}
