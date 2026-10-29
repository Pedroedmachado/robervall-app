import 'package:flutter/material.dart';

import '../calc.dart';
import '../format.dart';
import '../models.dart';
import '../modules.dart';
import '../store.dart';
import '../theme.dart';
import 'budget_tab.dart';
import 'claim_form_tab.dart';
import 'damage_tab.dart';
import 'os_tab.dart';
import 'photos_tab.dart';
import 'quote_preview_page.dart';
import 'timeline_tab.dart';
import 'widgets.dart';

class ClaimDetailPage extends StatefulWidget {
  const ClaimDetailPage({super.key, required this.claimId});
  final String claimId;

  @override
  State<ClaimDetailPage> createState() => _ClaimDetailPageState();
}

class _ClaimDetailPageState extends State<ClaimDetailPage> {
  Claim? _claim;

  @override
  void dispose() {
    final c = _claim;
    if (c != null) {
      // registra cliente/seguradora/regulador nos cadastros ao sair
      final store = _store;
      if (store != null && store.claims.contains(c)) {
        Future.microtask(() {
          if (store.isBlank(c)) {
            store.discardIfBlank(c);
          } else {
            store.rememberContactsFrom(c);
            store.changed(); // lista e painel refletem o que foi editado
          }
        });
        store.flush();
      }
    }
    super.dispose();
  }

  AppStore? _store;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    _store = store;
    final c = store.claimById(widget.claimId);
    _claim = c;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
            icon: Icons.delete_outline, text: 'Registro não encontrado.'),
      );
    }
    final totals = computeTotals(c, store.settings);
    final wide = isWide(context);
    final production = !gate.roleCan(Perm.valoresVer);
    final doneTasks = c.items.where((i) => i.approved && i.done).length;
    final allTasks = c.items.where((i) => i.approved).length;
    // modo produção: sem dados do cliente, sem orçamento e sem valores
    final tabs = <(IconData, String, Widget)>[
      if (!production)
        (Icons.description_outlined, 'Dados', ClaimFormTab(claim: c)),
      if (gate.active(Mod.vistoria)) ...[
        (Icons.car_repair, 'Avarias (${c.damages.length})', DamageTab(claim: c)),
        (Icons.photo_library_outlined, 'Fotos (${c.photos.length})',
            PhotosTab(claim: c)),
      ],
      if (!production)
        (Icons.request_quote_outlined, 'Orçamento (${c.items.length})',
            BudgetTab(claim: c)),
      if (gate.active(Mod.producao))
        (Icons.assignment_outlined, 'O.S. ($doneTasks/$allTasks)',
            OsTab(claim: c)),
      (Icons.timeline, 'Histórico', TimelineTab(claim: c)),
    ];

    return DefaultTabController(
      key: ValueKey('$production${tabs.length}'),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${c.number}${c.vehicle.plate.isEmpty ? '' : ' · ${c.vehicle.plate}'}',
                style: const TextStyle(fontWeight: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                c.vehicle.title,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            if (!production && gate.roleCan(Perm.sinistroEditar)) ...[
            IconButton(
              tooltip: 'Ver orçamento',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => QuotePreviewPage(claimId: c.id))),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'dup':
                    final copy = store.duplicate(c);
                    Navigator.of(context).pushReplacement(MaterialPageRoute(
                        builder: (_) => ClaimDetailPage(claimId: copy.id)));
                    toast(context, 'Cópia criada: ${copy.number}');
                  case 'del':
                    final ok = await confirm(
                      context,
                      'Excluir ${c.number}?',
                      'O registro, o orçamento e as fotos serão apagados deste aparelho. Isso não pode ser desfeito.',
                      ok: 'Excluir',
                      danger: true,
                    );
                    if (ok && context.mounted) {
                      _claim = null;
                      Navigator.pop(context);
                      await store.deleteClaim(c);
                    }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'dup',
                    child: ListTile(
                        leading: Icon(Icons.copy),
                        title: Text('Duplicar orçamento'))),
                PopupMenuItem(
                    value: 'del',
                    child: ListTile(
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text('Excluir'))),
              ],
            ),
            ],
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight((wide ? 72 : 46) + 44),
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _changeStatus(context, c),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            StatusChip(c.status),
                            const Icon(Icons.arrow_drop_down, size: 20),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        if (c.isOverdue)
                          const Flexible(
                            child: Text('Entrega atrasada',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600)),
                          )
                        else if (c.dueDate != null)
                          Flexible(
                            child: Text('Entrega ${date(c.dueDate)}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                    ),
                  ),
                ),
                TabBar(

                  isScrollable: !wide,
                  tabAlignment: wide ? TabAlignment.fill : TabAlignment.start,
                  tabs: [
                    for (final (icon, label, _) in tabs)
                      wide ? Tab(icon: Icon(icon), text: label) : Tab(text: label),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [for (final (_, _, page) in tabs) page],
        ),
        bottomNavigationBar:
            production
                ? null
                : _TotalBar(
                    claim: c,
                    totals: totals,
                    budgetTab: tabs.indexWhere((e) => e.$2.startsWith('Orçamento'))),
      ),
    );
  }

  Future<void> _changeStatus(BuildContext context, Claim c) async {
    final store = StoreScope.read(context);
    final picked = await showModalBottomSheet<ClaimStatus>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Alterar status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final s in ClaimStatus.values)
              ListTile(
                leading: Icon(Icons.circle, color: statusColor(s), size: 16),
                title: Text(s.label),
                trailing: s == c.status ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == c.status || !context.mounted) return;
    String? note;
    if (picked == ClaimStatus.aprovado) {
      final name = await _askText(context, 'Aprovado por',
          'Nome de quem aprovou (seguradora, regulador ou cliente)',
          initial: c.regulatorName.isNotEmpty
              ? c.regulatorName
              : (c.insurerName.isNotEmpty ? c.insurerName : c.customerName));
      if (name == null) return;
      c.approvedBy = name;
      c.approvedAt = DateTime.now();
      note = name.isEmpty ? null : 'por $name';
    } else if (picked == ClaimStatus.cancelado) {
      note = await _askText(context, 'Motivo', 'Motivo do cancelamento/recusa');
      if (note == null) return;
    }
    store.setStatus(c, picked, note: note);
  }
}

Future<String?> _askText(BuildContext context, String title, String hint,
    {String initial = ''}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
}

class _TotalBar extends StatelessWidget {
  const _TotalBar(
      {required this.claim, required this.totals, required this.budgetTab});
  final Claim claim;
  final int budgetTab;
  final BudgetTotals totals;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hasInsurer = claim.type == ClaimType.seguradora ||
        claim.type == ClaimType.terceiro;
    return Material(
      color: t.colorScheme.surfaceContainer,
      child: InkWell(
        // toque no total leva para a aba Orçamento
        onTap: () => DefaultTabController.of(context).animateTo(budgetTab),
        child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (totals.possibleTotalLoss)
                Tooltip(
                  message:
                      'Orçamento em ${pct(totals.fipePct)} do valor FIPE — possível perda total',
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.report, color: Colors.red),
                  ),
                ),
              Expanded(
                child: Text(
                  hasInsurer
                      ? 'Seguradora ${money(totals.insurerPays)} · Cliente ${money(totals.customerPays)}'
                      : '${totals.itemCount} itens · ${num2(totals.laborHours + totals.paintHours)} h',
                  style: t.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('Total ', style: t.textTheme.bodyMedium),
              Text(money(totals.total),
                  style: t.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: t.colorScheme.primary)),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
