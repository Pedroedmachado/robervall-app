import 'package:flutter/material.dart';

import '../calc.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import 'claim_detail_page.dart';
import 'widgets.dart';

Future<void> openClaim(BuildContext context, Claim c) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => ClaimDetailPage(claimId: c.id)));

Future<void> createAndOpenClaim(BuildContext context) {
  final store = StoreScope.read(context);
  final c = store.newClaim();
  return openClaim(context, c);
}

enum _Sort {
  updated('Última atualização'),
  created('Mais recentes'),
  due('Previsão de entrega'),
  value('Maior valor');

  const _Sort(this.label);
  final String label;
}

class ClaimsPage extends StatefulWidget {
  const ClaimsPage({super.key});

  @override
  State<ClaimsPage> createState() => _ClaimsPageState();
}

class _ClaimsPageState extends State<ClaimsPage> {
  String _q = '';
  ClaimStatus? _status;
  ClaimType? _type;
  bool _onlyOpen = true;
  bool _onlyOverdue = false;
  _Sort _sort = _Sort.updated;

  bool _match(Claim c) {
    if (_onlyOpen && !c.status.isOpen) return false;
    if (_onlyOverdue && !c.isOverdue) return false;
    if (_status != null && c.status != _status) return false;
    if (_type != null && c.type != _type) return false;
    if (_q.isEmpty) return true;
    final q = _q.toLowerCase();
    final plateQ = q.replaceAll('-', '');
    return [
      c.number,
      c.claimNumber,
      c.customerName,
      c.customerPhone,
      c.insurerName,
      c.vehicle.brand,
      c.vehicle.model,
      c.policyNumber,
    ].any((f) => f.toLowerCase().contains(q)) ||
        c.vehicle.plate.toLowerCase().replaceAll('-', '').contains(plateQ);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final list = store.claims.where(_match).toList();
    final totals = {for (final c in list) c.id: computeTotals(c, s)};
    switch (_sort) {
      case _Sort.updated:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _Sort.created:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _Sort.due:
        list.sort((a, b) {
          final da = a.dueDate, db = b.dueDate;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return da.compareTo(db);
        });
      case _Sort.value:
        list.sort((a, b) => totals[b.id]!.total.compareTo(totals[a.id]!.total));
    }
    final sum = list.fold<double>(0, (p, c) => p + totals[c.id]!.total);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sinistros e orçamentos'),
        actions: [
          PopupMenuButton<_Sort>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              for (final v in _Sort.values)
                PopupMenuItem(value: v, child: Text(v.label)),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => createAndOpenClaim(context),
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
                hintText: 'Buscar por placa, cliente, nº, seguradora, modelo…',
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
                _chip('Somente abertos', _onlyOpen,
                    (v) => setState(() => _onlyOpen = v)),
                _chip('Atrasados', _onlyOverdue,
                    (v) => setState(() => _onlyOverdue = v)),
                const VerticalDivider(indent: 10, endIndent: 10),
                for (final t in ClaimType.values)
                  _chip(t.label, _type == t,
                      (v) => setState(() => _type = v ? t : null)),
                const VerticalDivider(indent: 10, endIndent: 10),
                for (final st in ClaimStatus.values)
                  _chip(st.label, _status == st, (v) {
                    setState(() {
                      _status = v ? st : null;
                      if (v && !st.isOpen) _onlyOpen = false;
                    });
                  }, color: statusColor(st)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                      '${list.length} ${list.length == 1 ? 'registro' : 'registros'}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                Text('Total ${money(sum)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? EmptyState(
                    icon: Icons.search_off,
                    text: store.claims.isEmpty
                        ? 'Nenhum sinistro registrado ainda.'
                        : 'Nada encontrado com esses filtros.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) =>
                        _ClaimCard(list[i], totals[list[i].id]!),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, ValueChanged<bool> onSel,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSel,
        selectedColor: color?.withValues(alpha: 0.2),
        showCheckmark: false,
      ),
    );
  }
}

class _ClaimCard extends StatelessWidget {
  const _ClaimCard(this.c, this.t);
  final Claim c;
  final BudgetTotals t;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final store = StoreScope.of(context);
    final cover = c.photos.isEmpty ? null : store.photoFile(c.photos.first);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: th.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openClaim(context, c),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: cover != null && cover.existsSync()
                      ? Image.file(cover, fit: BoxFit.cover, cacheWidth: 160)
                      : Container(
                          color: th.colorScheme.primaryContainer,
                          child: Icon(Icons.directions_car,
                              color: th.colorScheme.onPrimaryContainer),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(c.number,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        if (c.vehicle.plate.isNotEmpty)
                          _PlateBadge(c.vehicle.plate),
                        StatusChip(c.status, dense: true),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(c.vehicle.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      [
                        c.customerName.isEmpty ? 'Sem cliente' : c.customerName,
                        if (c.insurerName.isNotEmpty) c.insurerName,
                        c.type.label,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: th.textTheme.bodySmall
                          ?.copyWith(color: th.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                        Icon(Icons.photo_camera_outlined,
                            size: 14, color: th.colorScheme.outline),
                        Text(' ${c.photos.length}  ',
                            style: th.textTheme.bodySmall),
                        Icon(Icons.list_alt,
                            size: 14, color: th.colorScheme.outline),
                        Text(' ${c.items.length}  ',
                            style: th.textTheme.bodySmall),
                        if (c.dueDate != null) ...[
                          Icon(Icons.event,
                              size: 14,
                              color: c.isOverdue
                                  ? Colors.red
                                  : th.colorScheme.outline),
                          Text(' ${date(c.dueDate)}',
                              style: th.textTheme.bodySmall?.copyWith(
                                  color: c.isOverdue ? Colors.red : null)),
                        ],
                            ],
                          ),
                        ),
                        if (t.possibleTotalLoss)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Tooltip(
                              message: 'Possível perda total',
                              child: Icon(Icons.report, size: 18, color: Colors.red),
                            ),
                          ),
                        Text(money(t.total),
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlateBadge extends StatelessWidget {
  const _PlateBadge(this.plate);
  final String plate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black87, width: 1.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(plate,
          style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 1)),
    );
  }
}
