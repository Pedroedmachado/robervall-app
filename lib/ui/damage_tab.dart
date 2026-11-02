import 'package:flutter/material.dart';

import '../complements.dart';
import '../models.dart';
import '../modules.dart';
import '../seed.dart';
import '../theme.dart';
import 'budget_tab.dart' show addComplements;
import 'widgets.dart';

/// Cor das avarias que já estavam no carro (não entram no orçamento).
const preDamageColor = Color(0xFF546E7A);

class DamageTab extends StatefulWidget {
  const DamageTab({super.key, required this.claim});
  final Claim claim;

  @override
  State<DamageTab> createState() => _DamageTabState();
}

class _DamageTabState extends State<DamageTab> {
  /// Marcando avarias que já existiam (true) ou do sinistro (false).
  bool _pre = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = widget.claim;
    final t = Theme.of(context);
    final production = !gate.can(Perm.orcamentoEditar);

    void cycle(CarRegion r) {
      final map = _pre ? c.preDamages : c.damages;
      final cur = map[r.id] ?? 0;
      final next = (cur + 1) % 4;
      if (next == 0) {
        map.remove(r.id);
      } else {
        map[r.id] = next;
      }
      store.touch(c);
    }

    void generate() {
      var added = 0;
      c.damages.forEach((id, sev) {
        final r = regionById(id);
        if (r == null) return;
        // uma linha por peça, juntando as operações sugeridas
        final byPart = <String, Set<ItemOp>>{};
        for (final (desc, op) in r.suggestions) {
          byPart.putIfAbsent(desc, () => {}).add(op);
        }
        byPart.forEach((desc, ops) {
          final exists = c.items.any((it) =>
              it.description.trim().toLowerCase() == desc.toLowerCase());
          if (exists) return;
          // avaria pesada em lataria vira troca da peça
          final replace = ops.contains(ItemOp.troca) ||
              (ops.contains(ItemOp.reparo) && sev == 3);
          final labor = replace
              ? suggestedLaborHours(ItemOp.troca, sev)
              : (ops.contains(ItemOp.reparo)
                  ? suggestedLaborHours(ItemOp.reparo, sev)
                  : 0.0);
          final paint = ops.contains(ItemOp.pintura)
              ? suggestedPaintHours(ItemOp.pintura, sev)
              : 0.0;
          final part = BudgetItem(
            description: desc,
            region: id,
            op: opFor(
                service: false,
                replace: replace,
                laborHours: labor,
                paintHours: paint),
            laborHours: labor,
            paintHours: paint,
          );
          c.items.add(part);
          added++;
          // troca: já entram os complementos (vidro, forro, chicote...)
          if (replace) {
            final comps = [
              for (final (comp, on) in complementsFor(part))
                if (on) comp
            ];
            if (comps.isNotEmpty) addComplements(c, part, comps);
          }
        });
      });
      if (added > 0) {
        c.timeline.add(TimelineEvent(
            text: '$added peças geradas a partir do mapa de avarias'));
      }
      store.touch(c);
      toast(
          context,
          added == 0
              ? 'Os itens dessas avarias já estão no orçamento.'
              : '$added ${added == 1 ? 'peça adicionada' : 'peças adicionadas'} ao orçamento. Confira preços e horas na aba Orçamento.');
    }

    final diagram = AspectRatio(
      aspectRatio: 0.55,
      child: LayoutBuilder(builder: (context, cons) {
        final w = cons.maxWidth, h = cons.maxHeight;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _CarPainter(
                  body: t.colorScheme.surfaceContainerHighest,
                  line: t.colorScheme.outline,
                ),
              ),
            ),
            for (final r in carRegions)
              Positioned(
                left: r.left * w,
                top: r.top * h,
                width: r.width * w,
                height: r.height * h,
                child: _RegionBox(
                  region: r,
                  severity: c.damages[r.id] ?? 0,
                  pre: c.preDamages[r.id] ?? 0,
                  onTap: () => cycle(r),
                ),
              ),
          ],
        );
      }),
    );

    final marked = carRegions.where((r) => c.damages.containsKey(r.id)).toList();
    final preMarked =
        carRegions.where((r) => c.preDamages.containsKey(r.id)).toList();

    final modeBar = SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
            value: false,
            label: Text('Avaria do sinistro'),
            icon: Icon(Icons.car_crash_outlined)),
        ButtonSegment(
            value: true,
            label: Text('Pré-existente'),
            icon: Icon(Icons.history)),
      ],
      selected: {_pre},
      onSelectionChanged: (sel) => setState(() => _pre = sel.first),
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReceptionCard(claim: c),
        SectionCard(
          title: 'Como usar',
          icon: Icons.touch_app_outlined,
          children: [
            Text(_pre
                ? 'Marcando o que JÁ ESTAVA no carro quando chegou (risco, amassado antigo…). Isso protege a oficina e não entra no orçamento.'
                : 'Toque nas partes do carro para marcar a avaria do sinistro. Cada toque muda a intensidade: leve → média → pesada → sem avaria.'),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 8, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                      color: preDamageColor,
                      borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 6),
                const Text('Pré-existente (PE)'),
              ]),
              for (final e in severityLabels.entries)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                        color: severityColor(e.key),
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 6),
                  Text(e.value),
                ]),
            ]),
          ],
        ),
        SectionCard(
          title: 'Avarias marcadas (${marked.length})',
          icon: Icons.car_crash_outlined,
          trailing: marked.isEmpty
              ? null
              : TextButton(
                  onPressed: () async {
                    if (await confirm(context, 'Limpar mapa?',
                        'Remove todas as marcações (os itens do orçamento continuam).')) {
                      c.damages.clear();
                      store.touch(c);
                    }
                  },
                  child: const Text('Limpar'),
                ),
          children: [
            if (marked.isEmpty)
              const Text('Nenhuma avaria marcada.')
            else
              for (final r in marked)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.circle,
                      color: severityColor(c.damages[r.id]!), size: 16),
                  title: Text(r.label),
                  subtitle: Text(severityLabels[c.damages[r.id]] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      c.damages.remove(r.id);
                      store.touch(c);
                    },
                  ),
                ),
            if (marked.isNotEmpty && !production) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: generate,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Gerar itens no orçamento'),
              ),
            ],
          ],
        ),
        SectionCard(
          title: 'Pré-existentes (${preMarked.length})',
          icon: Icons.history,
          children: [
            if (preMarked.isEmpty)
              const Text(
                  'Nada marcado. Use "Pré-existente" acima do desenho para registrar o que o carro já tinha ao chegar.')
            else
              for (final r in preMarked)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.circle,
                      color: preDamageColor, size: 16),
                  title: Text(r.label),
                  subtitle: Text(
                      'Já estava no carro · ${(severityLabels[c.preDamages[r.id]] ?? '').toLowerCase()}'),
                  trailing: IconButton(
                    tooltip: 'Tirar',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      c.preDamages.remove(r.id);
                      store.touch(c);
                    },
                  ),
                ),
          ],
        ),
      ],
    );

    return LayoutBuilder(builder: (context, cons) {
      if (cons.maxWidth >= 760) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 340,
                  child: Column(children: [
                    modeBar,
                    const SizedBox(height: 12),
                    diagram,
                  ])),
              const SizedBox(width: 24),
              Expanded(child: side),
            ],
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          modeBar,
          const SizedBox(height: 12),
          Center(child: SizedBox(width: 300, child: diagram)),
          const SizedBox(height: 16),
          side,
        ],
      );
    });
  }
}

class _RegionBox extends StatelessWidget {
  const _RegionBox(
      {required this.region,
      required this.severity,
      this.pre = 0,
      required this.onTap});
  final CarRegion region;
  final int severity;
  final int pre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = severity != 0
        ? severityColor(severity)
        : (pre != 0 ? preDamageColor : null);
    final label = [
      if (severity != 0) '$severity',
      if (pre != 0) 'PE',
    ].join('·');
    return Tooltip(
      message: region.label,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Material(
          color: color?.withValues(alpha: 0.75) ??
              t.colorScheme.primary.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
                color: color ?? t.colorScheme.primary.withValues(alpha: 0.35)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: label.isEmpty
                ? null
                : Center(
                    child: FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Text(
                          label,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _CarPainter extends CustomPainter {
  _CarPainter({required this.body, required this.line});
  final Color body;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fill = Paint()..color = body;
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final wheel = Paint()..color = line.withValues(alpha: 0.8);

    // rodas
    for (final y in [0.17, 0.70]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.08, h * y, w * 0.07, h * 0.12),
              const Radius.circular(6)),
          wheel);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.85, h * y, w * 0.07, h * 0.12),
              const Radius.circular(6)),
          wheel);
    }
    // carroceria
    final bodyRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.15, h * 0.01, w * 0.70, h * 0.95),
      topLeft: Radius.circular(w * 0.18),
      topRight: Radius.circular(w * 0.18),
      bottomLeft: Radius.circular(w * 0.12),
      bottomRight: Radius.circular(w * 0.12),
    );
    canvas.drawRRect(bodyRect, fill);
    canvas.drawRRect(bodyRect, stroke);
    // indicação da traseira (frente fica para cima)
    final tp = TextPainter(
      text: TextSpan(
          text: 'TRASEIRA',
          style: TextStyle(
              color: line, fontSize: 10, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((w - tp.width) / 2, h * 0.965));
  }

  @override
  bool shouldRepaint(covariant _CarPainter old) =>
      old.body != body || old.line != line;
}


/// Checklist de entrada: data, combustível, km, itens e observação.
class ReceptionCard extends StatelessWidget {
  const ReceptionCard({super.key, required this.claim});
  final Claim claim;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = claim;
    final r = c.reception;
    final t = Theme.of(context);
    String two(int n) => n.toString().padLeft(2, '0');
    return SectionCard(
      title: 'Checklist de entrada',
      icon: Icons.fact_check_outlined,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              r.at == null
                  ? 'Entrada não registrada'
                  : 'Entrada: ${two(r.at!.day)}/${two(r.at!.month)}/${r.at!.year} às ${two(r.at!.hour)}:${two(r.at!.minute)}',
              style: t.textTheme.bodyMedium,
            ),
          ),
          TextButton.icon(
            onPressed: () {
              r.at = DateTime.now();
              c.timeline.add(TimelineEvent(text: 'Entrada do veículo registrada'));
              store.touch(c);
            },
            icon: const Icon(Icons.login, size: 18),
            label: Text(r.at == null ? 'Registrar agora' : 'Atualizar'),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Combustível', style: t.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final (i, f) in fuelLevels.indexed)
            ChoiceChip(
              label: Text(f),
              selected: r.fuel == i,
              onSelected: (_) {
                r.fuel = r.fuel == i ? -1 : i;
                store.touch(c);
              },
            ),
        ]),
        const SizedBox(height: 12),
        BoundField(
          label: 'Km na entrada',
          value: c.vehicle.km,
          keyboard: TextInputType.number,
          onChanged: (v) {
            c.vehicle.km = v;
            store.saveLater();
          },
        ),
        const SizedBox(height: 12),
        Text('Itens que estão no carro', style: t.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final i in receptionItems)
            FilterChip(
              label: Text(i),
              selected: r.items.contains(i),
              onSelected: (b) {
                b ? r.items.add(i) : r.items.remove(i);
                store.touch(c);
              },
            ),
        ]),
        const SizedBox(height: 12),
        BoundField(
          label: 'Observação da entrada',
          hint: 'Ex.: cliente deixou cadeirinha no banco',
          value: r.notes,
          maxLines: 2,
          onChanged: (v) {
            r.notes = v;
            store.saveLater();
          },
        ),
        const SizedBox(height: 6),
        Text('Fotos da entrada: aba Fotos, categoria "Entrada (recepção)".',
            style: t.textTheme.bodySmall),
      ],
    );
  }
}
