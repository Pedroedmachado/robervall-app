import 'package:flutter/material.dart';

import '../calc.dart';
import '../finance.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import 'claims_page.dart';
import 'widgets.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage(
      {super.key, required this.onOpenClaims, this.onOpenFinance});
  final VoidCallback onOpenClaims;
  final VoidCallback? onOpenFinance;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final claims = store.claims;
    final now = DateTime.now();

    double openValue = 0, monthValue = 0, insurerOpen = 0;
    int overdue = 0, waiting = 0, repairing = 0, open = 0, monthCount = 0;
    final byStatus = <ClaimStatus, int>{};
    for (final c in claims) {
      byStatus[c.status] = (byStatus[c.status] ?? 0) + 1;
      final t = computeTotals(c, s);
      if (c.status.isOpen) {
        open++;
        openValue += t.total;
        insurerOpen += t.insurerPays;
      }
      if (c.isOverdue) overdue++;
      if (c.status == ClaimStatus.aguardandoAprovacao) waiting++;
      if (c.status == ClaimStatus.emReparo) repairing++;
      final closedAt = closedDate(c);
      if (isClosedStatus(c.status) &&
          closedAt.year == now.year &&
          closedAt.month == now.month) {
        monthValue += t.total;
        monthCount++;
      }
    }

    final upcoming = claims
        .where((c) => c.status.isOpen && c.dueDate != null)
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    final recent = [...claims]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final fin = summarize(
        store.claims, store.entries, s, Period.month(now.year, now.month));

    final kpis = [
      _Kpi('Em aberto', '$open', Icons.folder_open, brandSeed),
      _Kpi('Aguardando aprovação', '$waiting', Icons.hourglass_top,
          statusColor(ClaimStatus.aguardandoAprovacao)),
      _Kpi('Em reparo', '$repairing', Icons.build,
          statusColor(ClaimStatus.emReparo)),
      _Kpi('Atrasados', '$overdue', Icons.warning_amber,
          overdue > 0 ? Colors.red : Colors.grey),
      _Kpi('Valor em aberto', money(openValue), Icons.request_quote,
          const Color(0xFF00897B)),
      _Kpi('A receber de seguradoras', money(insurerOpen), Icons.shield,
          const Color(0xFF5E35B1)),
      _Kpi('Fechado no mês', money(monthValue), Icons.trending_up,
          const Color(0xFF2E7D32),
          sub: '$monthCount ${monthCount == 1 ? 'serviço' : 'serviços'}'),
      _Kpi(
        fin.profit >= 0 ? 'Lucro do mês' : 'Prejuízo do mês',
        money(fin.profit),
        Icons.account_balance_wallet,
        fin.profit >= 0 ? const Color(0xFF2E7D32) : Colors.red,
        sub: 'gastos ${money(fin.expenses)}',
        onTap: onOpenFinance,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(s.shopName.isEmpty ? 'Funilar' : s.shopName,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => createAndOpenClaim(context),
              icon: const Icon(Icons.add),
              label: const Text('Novo sinistro'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LayoutBuilder(builder: (context, cons) {
            final cols = (cons.maxWidth / 220).floor().clamp(2, 4);
            const gap = 12.0;
            final w = (cons.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final k in kpis) SizedBox(width: w, child: _KpiCard(k)),
              ],
            );
          }),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, cons) {
            final statusCard = SectionCard(
              title: 'Por status',
              icon: Icons.donut_large,
              children: [
                if (claims.isEmpty)
                  const Text('Nenhum registro ainda.')
                else
                  for (final st in ClaimStatus.values)
                    if ((byStatus[st] ?? 0) > 0)
                      _StatusBar(
                          status: st,
                          count: byStatus[st]!,
                          total: claims.length),
              ],
            );
            final dueCard = SectionCard(
              title: 'Próximas entregas',
              icon: Icons.event_available,
              children: [
                if (upcoming.isEmpty)
                  const Text('Sem previsões de entrega cadastradas.')
                else
                  for (final c in upcoming.take(6)) _ClaimTile(c, showDue: true),
              ],
            );
            if (cons.maxWidth < 760) {
              return Column(children: [statusCard, dueCard]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: statusCard),
                const SizedBox(width: 12),
                Expanded(child: dueCard),
              ],
            );
          }),
          SectionCard(
            title: 'Atualizados recentemente',
            icon: Icons.history,
            trailing: TextButton(
                onPressed: onOpenClaims, child: const Text('Ver todos')),
            children: [
              if (recent.isEmpty)
                EmptyState(
                  icon: Icons.car_crash_outlined,
                  text:
                      'Comece registrando um sinistro ou orçamento.\nVocê pode tirar fotos, marcar avarias no carro e montar o orçamento.',
                  action: FilledButton.icon(
                    onPressed: () => createAndOpenClaim(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Novo sinistro'),
                  ),
                )
              else
                for (final c in recent.take(8)) _ClaimTile(c),
            ],
          ),
        ],
      ),
    );
  }
}

class _Kpi {
  final String label, value;
  final IconData icon;
  final Color color;
  final String? sub;
  final VoidCallback? onTap;
  _Kpi(this.label, this.value, this.icon, this.color, {this.sub, this.onTap});
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(this.k);
  final _Kpi k;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: k.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(k.icon, color: k.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(k.value,
                      style: t.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (k.sub != null)
                  Text(k.sub!, style: t.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
    if (k.onTap == null) return card;
    return InkWell(
        borderRadius: BorderRadius.circular(14), onTap: k.onTap, child: card);
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar(
      {required this.status, required this.count, required this.total});
  final ClaimStatus status;
  final int count, total;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(status.label)),
            Text('$count', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : count / total,
              minHeight: 8,
              color: c,
              backgroundColor: c.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile(this.c, {this.showDue = false});
  final Claim c;
  final bool showDue;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = computeTotals(c, store.settings);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => openClaim(context, c),
      leading: CircleAvatar(
        backgroundColor: statusColor(c.status).withValues(alpha: 0.15),
        child: Icon(Icons.directions_car, color: statusColor(c.status)),
      ),
      title: Text(
        '${c.number} · ${c.vehicle.plate.isEmpty ? c.vehicle.title : c.vehicle.plate}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        showDue
            ? 'Entrega: ${date(c.dueDate)}${c.isOverdue ? ' (atrasado)' : ''} · ${c.customerName}'
            : '${c.customerName.isEmpty ? 'Sem cliente' : c.customerName} · ${c.status.label}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: c.isOverdue && showDue ? const TextStyle(color: Colors.red) : null,
      ),
      trailing: Text(money(t.total),
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
