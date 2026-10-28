import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

class TimelineTab extends StatefulWidget {
  const TimelineTab({super.key, required this.claim});
  final Claim claim;

  @override
  State<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<TimelineTab> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _add() {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    widget.claim.timeline.add(TimelineEvent(text: text));
    _ctl.clear();
    StoreScope.read(context).touch(widget.claim);
  }

  @override
  Widget build(BuildContext context) {
    StoreScope.of(context);
    final t = Theme.of(context);
    final events = widget.claim.timeline.reversed.toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText:
                        'Anotar acompanhamento (ligação, peça chegou, perito visitou…)',
                    prefixIcon: Icon(Icons.edit_note),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                  onPressed: _add, icon: const Icon(Icons.send), tooltip: 'Anotar'),
            ],
          ),
        ),
        Expanded(
          child: events.isEmpty
              ? const EmptyState(icon: Icons.timeline, text: 'Sem histórico.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: events.length,
                  itemBuilder: (context, i) {
                    final e = events[i];
                    final last = i == events.length - 1;
                    final color = e.isStatus ? brandSeed : t.colorScheme.outline;
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 24,
                            child: Column(
                              children: [
                                const SizedBox(height: 6),
                                Icon(
                                    e.isStatus
                                        ? Icons.flag_circle
                                        : Icons.circle,
                                    size: e.isStatus ? 18 : 10,
                                    color: color),
                                if (!last)
                                  Expanded(
                                    child: Container(
                                        width: 2,
                                        color: t.colorScheme.outlineVariant),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.text,
                                      style: TextStyle(
                                          fontWeight: e.isStatus
                                              ? FontWeight.w700
                                              : FontWeight.w400)),
                                  Text(dateTime(e.at),
                                      style: t.textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
