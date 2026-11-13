import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../team.dart';
import '../theme.dart';
import 'claims_page.dart';
import 'widgets.dart';

/// Sub-aba Produção: quantas peças/serviços cada funcionário fez nos últimos
/// 7, 15 e 30 dias, com todos os carros em que trabalhou.
class ProductionView extends StatefulWidget {
  const ProductionView({super.key});

  @override
  State<ProductionView> createState() => _ProductionViewState();
}

String _n(double v) => num2(v);

String _pieces(double v) => '${_n(v)} ${v == 1 ? 'peça/serviço' : 'peças/serviços'}';

String _cars(int n) => '$n ${n == 1 ? 'carro' : 'carros'}';

class _ProductionViewState extends State<ProductionView> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final now = DateTime.now();
    final list = productionReport(claims: store.claims, contacts: store.contacts, now: now);
    final total = list.fold(0.0, (a, r) => a + r.pieces(_days, now));
    final cars = {
      for (final r in list)
        for (final j in r.within(_days, now)) j.claim.id
    }.length;
    final openCars = {
      for (final r in list)
        for (final j in r.open) j.claim.id
    }.length;

    final resumo = SectionCard(
      title: 'Produção nos últimos $_days dias',
      icon: Icons.fact_check_outlined,
      children: [
        Row(children: [
          const Expanded(child: Text('Peças e serviços feitos pela equipe')),
          Text(_n(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ]),
        Row(children: [
          const Expanded(child: Text('Carros concluídos')),
          Text('$cars', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        Row(children: [
          const Expanded(child: Text('Carros em andamento agora')),
          Text('$openCars', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Text(
            'Conta as peças/serviços da função de cada um (as mesmas do pagamento por peça) nos carros concluídos no período. Vale quem está escalado na equipe do carro, no orçamento.',
            style: t.textTheme.bodySmall),
      ],
    );

    Widget windowChip(WorkerProduction r, int d) {
      final sel = d == _days;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _days = d),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: sel ? t.colorScheme.secondaryContainer : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.colorScheme.outlineVariant),
            ),
            child: Column(children: [
              Text('$d dias', style: t.textTheme.bodySmall),
              Text(_n(r.pieces(d, now)),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              Text(_cars(r.cars(d, now)), style: t.textTheme.bodySmall),
            ]),
          ),
        ),
      );
    }

    Widget jobTile(ProductionJob j) => Theme(
          data: t.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('prod-${j.claim.id}-${j.role.name}-${j.done}'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(left: 8, bottom: 6),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(
                '${j.claim.number}${j.claim.vehicle.plate.isEmpty ? '' : ' · ${j.claim.vehicle.plate}'} · ${j.claim.vehicle.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${j.role.worker} · ${_pieces(j.pieces)} · ${j.done ? 'concluído em ${date(j.date)}' : 'em andamento (${j.claim.status.label})'}'),
            children: [
              for (final it in j.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text('• ${it.description.isEmpty ? 'Item' : it.description}'
                      '${it.qty > 1 ? ' (${_n(it.qty)}×)' : ''}'),
                ),
              if (j.items.isEmpty)
                Text('Quantidade informada na equipe do carro.', style: t.textTheme.bodySmall),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openClaim(context, j.claim),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Abrir o carro'),
                ),
              ),
            ],
          ),
        );

    final cards = <Widget>[
      for (final r in list)
        Card(
          key: ValueKey('producao-${r.name}'),
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: t.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor: t.colorScheme.secondaryContainer,
                  child: Text(r.name.isEmpty ? '?' : r.name[0].toUpperCase()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(
                      [
                        if (r.roles.isNotEmpty) r.roles.map((e) => e.worker).join(', '),
                        if (r.worker != null) r.worker!.workerSummary,
                      ].join(' · '),
                      style: t.textTheme.bodySmall,
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [for (final d in const [7, 15, 30]) windowChip(r, d)]),
              const SizedBox(height: 8),
              Text('Trabalhos dos últimos $_days dias (${r.within(_days, now).length})',
                  style: t.textTheme.labelLarge),
              if (r.within(_days, now).isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Nenhum carro concluído nesse período.',
                      style: t.textTheme.bodySmall),
                ),
              for (final j in r.within(_days, now)) jobTile(j),
              if (r.open.isNotEmpty) ...[
                const Divider(height: 16),
                Text('Em andamento agora (${r.open.length}) · ${_pieces(r.openPieces)}',
                    style: t.textTheme.labelLarge),
                for (final j in r.open) jobTile(j),
              ],
            ]),
          ),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7 dias')),
                    ButtonSegment(value: 15, label: Text('15 dias')),
                    ButtonSegment(value: 30, label: Text('30 dias')),
                  ],
                  selected: {_days},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _days = s.first),
                ),
              ),
              resumo,
              const SizedBox(height: 4),
              if (cards.isEmpty)
                const EmptyState(
                    icon: Icons.fact_check_outlined,
                    text:
                        'Ninguém produziu nos últimos 30 dias. Escale a equipe no orçamento do carro (aba Orçamento › Equipe): quando o carro é concluído, as peças de cada um aparecem aqui.')
              else
                ...cards,
            ]),
          ),
        ),
      ],
    );
  }
}
