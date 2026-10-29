import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../modules.dart';
import '../theme.dart';
import 'widgets.dart';

/// Libera uma ação: se o usuário logado tem a permissão, segue; senão pede
/// que alguém autorizado (gestor, almoxarife…) confirme com o PIN dele.
Future<bool> authorize(BuildContext context, Perm p, {String reason = ''}) async {
  final store = StoreScope.read(context);
  if (gate.readOnly) {
    toast(context, 'Licença inválida ou ausente: somente consulta.');
    return false;
  }
  if (gate.can(p)) return true;
  final allowed = store.activeUsers.where((u) => u.can(p)).toList();
  if (allowed.isEmpty) {
    toast(context, 'Nenhum usuário tem permissão: ${p.label}.');
    return false;
  }
  var who = allowed.first;
  final pinCtl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Autorização'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(reason.isEmpty ? 'Precisa de alguém com permissão: ${p.label}.' : reason),
          const SizedBox(height: 12),
          DropdownButtonFormField<AppUser>(
            initialValue: who,
            decoration: const InputDecoration(labelText: 'Quem autoriza'),
            items: [
              for (final u in allowed)
                DropdownMenuItem(value: u, child: Text('${u.name} · ${u.role.label}')),
            ],
            onChanged: (u) => setS(() => who = u ?? who),
          ),
          const SizedBox(height: 12),
          pinField(pinCtl, onDone: () => Navigator.pop(ctx, true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Autorizar')),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  final good = await store.authorizeOnce(who, pinCtl.text.trim(), p);
  if (!good && context.mounted) toast(context, 'PIN incorreto.');
  return good;
}

/// Campo de PIN (só números, escondido).
Widget pinField(TextEditingController ctl, {VoidCallback? onDone, String label = 'PIN'}) =>
    TextField(
      key: ValueKey('pin-$label'),
      controller: ctl,
      autofocus: true,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8),
      ],
      decoration: InputDecoration(labelText: label),
      onSubmitted: (_) => onDone?.call(),
    );

/// Mostra o erro de acesso (módulo desligado / sem permissão) sem quebrar.
void runGuarded(BuildContext context, void Function() action) {
  try {
    action();
  } on AccessDenied catch (e) {
    toast(context, e.message);
  }
}
