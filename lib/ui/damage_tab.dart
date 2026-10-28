import 'package:flutter/material.dart';

import '../models.dart';
import '../seed.dart';
import '../theme.dart';
import 'widgets.dart';

class DamageTab extends StatelessWidget {
  const DamageTab({super.key, required this.claim});
  final Claim claim;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = claim;
    final t = Theme.of(context);

    void cycle(CarRegion r) {
      final cur = c.damages[r.id] ?? 0;
      final next = (cur + 1) % 4;
      if (next == 0) {
        c.damages.remove(r.id);
      } else {
        c.damages[r.id] = next;
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
          c.items.add(BudgetItem(
            description: desc,
            region: id,
            op: opFor(
                service: false,
                replace: replace,
                laborHours: labor,
                paintHours: paint),
            laborHours: labor,
            paintHours: paint,
          ));
          added++;
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
                  onTap: () => cycle(r),
                ),
              ),
          ],
        );
      }),
    );

    final marked = carRegions.where((r) => c.damages.containsKey(r.id)).toList();

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Como usar',
          icon: Icons.touch_app_outlined,
          children: [
            const Text(
                'Toque nas partes do carro para marcar a avaria. Cada toque muda a intensidade: leve → média → pesada → sem avaria.'),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 8, children: [
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
            if (marked.isNotEmpty) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: generate,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Gerar itens no orçamento'),
              ),
            ],
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
              SizedBox(width: 340, child: diagram),
              const SizedBox(width: 24),
              Expanded(child: side),
            ],
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
      {required this.region, required this.severity, required this.onTap});
  final CarRegion region;
  final int severity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = severity == 0 ? null : severityColor(severity);
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
            child: severity == 0
                ? null
                : Center(
                    child: Text(
                      '$severity',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900),
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
