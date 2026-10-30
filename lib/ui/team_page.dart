import 'package:flutter/material.dart';

import '../finance.dart';
import '../format.dart';
import '../team.dart';
import '../theme.dart';
import 'claims_page.dart';
import 'widgets.dart';

const _good = Color(0xFF2E7D32);
const _bad = Color(0xFFC62828);

/// Sub-aba Equipe: material e lucro de cada funcionário no período.
class TeamView extends StatelessWidget {
  const TeamView({super.key, required this.period, required this.header});
  final Period period;
  final Widget header;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final list = teamReport(
        claims: store.claims,
        contacts: store.contacts,
        settings: store.settings,
        period: period);
    final material = list.fold(0.0, (a, r) => a + r.material);
    final profit = list.fold(0.0, (a, r) => a + r.profit);
    final revenue = list.fold(0.0, (a, r) => a + r.revenue);

    Widget kv(String k, double v, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [
            Expanded(child: Text(k, style: bold ? const TextStyle(fontWeight: FontWeight.w800) : null)),
            Text(money(v),
                style: TextStyle(
                    color: color,
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
          ]),
        );

    final resumo = SectionCard(
      title: 'Equipe no período',
      icon: Icons.engineering_outlined,
      children: [
        kv('Serviços feitos (valor no orçamento)', revenue),
        kv('Material usado', -material, color: _bad),
        kv(profit >= 0 ? 'Lucro gerado pela equipe' : 'Prejuízo da equipe', profit,
            color: profit >= 0 ? _good : _bad, bold: true),
        const SizedBox(height: 6),
        Text(
            'Lucro gerado = valor dos serviços dele nos carros concluídos no período − o que ele recebe por esses carros − o material liberado para ele no período.',
            style: t.textTheme.bodySmall),
      ],
    );

    final cards = <Widget>[
      for (final r in list)
        Card(
          key: ValueKey('equipe-${r.name}'),
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: t.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  CircleAvatar(
                    backgroundColor: t.colorScheme.secondaryContainer,
                    child: Text(r.name.isEmpty ? '?' : r.name[0].toUpperCase()),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(
                        [
                          if (r.roles.isNotEmpty) r.roles.map((e) => e.worker).join(', '),
                          if (r.worker != null) r.worker!.workerSummary,
                        ].join(' · '),
                        style: t.textTheme.bodySmall,
                      ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(money(r.profit),
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: r.profit >= 0 ? _good : _bad)),
                    Text(r.profit >= 0 ? 'lucro gerado' : 'prejuízo',
                        style: t.textTheme.bodySmall),
                  ]),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Expanded(child: Text('Carros concluídos no período')),
                  Text('${r.cars.length}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
                kv('Serviços dele (valor no orçamento)', r.revenue),
                kv(r.salaried ? 'Pagamento por carro (assalariado)' : 'Pagamento dele', -r.pay,
                    color: _bad),
                kv('Material usado no mês (${r.materialCount} ${r.materialCount == 1 ? 'saída' : 'saídas'})',
                    -r.material,
                    color: _bad),
                if (r.revenue > 0)
                  Text('Margem ${pct(r.marginPct)}', style: t.textTheme.bodySmall),
                if (r.salaried)
                  Text('Salário fica nos gastos fixos (aba Vendas), não por carro.',
                      style: t.textTheme.bodySmall),
                if (r.cars.isNotEmpty)
                  Theme(
                    data: t.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('Ver os ${r.cars.length} ${r.cars.length == 1 ? 'carro' : 'carros'}',
                          style: t.textTheme.labelLarge),
                      children: [
                        for (final c in r.cars)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onTap: () => openClaim(context, c.claim),
                            title: Text(
                                '${c.claim.number}${c.claim.vehicle.plate.isEmpty ? '' : ' · ${c.claim.vehicle.plate}'} · ${c.role.worker}'),
                            subtitle: Text(
                                'serviços ${money(c.revenue)} · pagamento ${money(c.pay)} · material ${money(c.material)}'),
                            trailing: Text(money(c.profit),
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: c.profit >= 0 ? _good : _bad)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 8),
                resumo,
                const SizedBox(height: 4),
                if (cards.isEmpty)
                  const EmptyState(
                      icon: Icons.engineering_outlined,
                      text:
                          'Nada neste período. Escale a equipe no orçamento do carro e libere os insumos para o funcionário na O.S.: aqui aparece quanto cada um gastou e gerou.')
                else
                  ...cards,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
