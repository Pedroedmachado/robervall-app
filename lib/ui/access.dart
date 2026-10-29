import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'widgets.dart';

/// Pede o PIN do gestor quando o aparelho está no modo produção.
/// No modo gestor libera direto.
Future<bool> requireManager(BuildContext context, {String reason = ''}) async {
  final store = StoreScope.read(context);
  if (!store.settings.productionMode) return true;
  final pin = store.settings.managerPin;
  if (pin.isEmpty) return true;
  final typed = await _askPin(context, 'PIN do gestor',
      reason.isEmpty ? 'Só o gestor libera esta ação.' : reason);
  if (typed == null) return false;
  if (typed == pin) return true;
  if (context.mounted) toast(context, 'PIN incorreto.');
  return false;
}

/// Coloca o aparelho no modo produção (cria o PIN se ainda não existe).
Future<void> enterProductionMode(BuildContext context) async {
  final store = StoreScope.read(context);
  if (store.settings.managerPin.isEmpty) {
    final pin = await _askPin(context, 'Crie o PIN do gestor',
        'Com ele você volta ao modo gestor e libera insumos. Use 4 a 8 números.',
        create: true);
    if (pin == null) return;
    store.settings.managerPin = pin;
  }
  store.setProductionMode(true);
  if (context.mounted) {
    toast(context, 'Modo produção ligado: valores escondidos.');
  }
}

/// Volta ao modo gestor (pede o PIN).
Future<void> leaveProductionMode(BuildContext context) async {
  final store = StoreScope.read(context);
  if (!await requireManager(context,
      reason: 'Digite o PIN para voltar ao modo gestor.')) {
    return;
  }
  store.setProductionMode(false);
}

/// Troca o PIN (no modo gestor).
Future<void> changeManagerPin(BuildContext context) async {
  final store = StoreScope.read(context);
  final pin = await _askPin(context, 'Novo PIN do gestor',
      'Use 4 a 8 números.', create: true);
  if (pin == null) return;
  store.settings.managerPin = pin;
  store.changed();
  if (context.mounted) toast(context, 'PIN alterado.');
}

Future<String?> _askPin(BuildContext context, String title, String hint,
    {bool create = false}) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void done() {
        final v = ctl.text.trim();
        if (create && (v.length < 4 || v.length > 8)) {
          toast(ctx, 'O PIN precisa ter de 4 a 8 números.');
          return;
        }
        Navigator.pop(ctx, v);
      }

      return AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(hint),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('pin'),
            controller: ctl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: const InputDecoration(labelText: 'PIN'),
            onSubmitted: (_) => done(),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(onPressed: done, child: const Text('OK')),
        ],
      );
    },
  );
}
