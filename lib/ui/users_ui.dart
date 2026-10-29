import 'package:flutter/material.dart';

import '../models.dart' show newId;
import '../modules.dart';
import '../theme.dart';
import 'access.dart';
import 'widgets.dart';

/// Tela de entrada quando há mais de um usuário.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  AppUser? _who;
  final _pin = TextEditingController();

  Future<void> _enter() async {
    final store = StoreScope.read(context);
    final u = _who;
    if (u == null) return;
    final ok = await store.login(u, _pin.text.trim());
    if (!ok && mounted) {
      _pin.clear();
      toast(context, 'PIN incorreto.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final users = store.activeUsers;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text('Funilar', textAlign: TextAlign.center,
                    style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: t.colorScheme.primary)),
                const SizedBox(height: 4),
                Text(store.settings.shopName, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Text('Quem está usando?', style: t.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final u in users)
                  Card(
                    elevation: 0,
                    color: _who == u ? t.colorScheme.secondaryContainer : null,
                    child: ListTile(
                      key: ValueKey('login-${u.name}'),
                      leading: const Icon(Icons.person_outline),
                      title: Text(u.name),
                      subtitle: Text(u.role.label),
                      onTap: () async {
                        setState(() => _who = u);
                        if (u.pinHash.isEmpty) await _enter();
                      },
                    ),
                  ),
                if (_who != null && _who!.pinHash.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  pinField(_pin, onDone: _enter),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _enter, child: const Text('Entrar')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Usuários e papéis (Administrador da empresa).
class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Usuários e permissões')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Novo usuário'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          Text(
              store.users.isEmpty
                  ? 'Hoje o app é de uso individual (acesso total, sem login). O primeiro usuário precisa ser Administrador; com dois ou mais, o app pede login ao abrir.'
                  : 'Com dois ou mais usuários ativos o app pede login. Usuários não são apagados: são desativados.',
              style: t.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final u in store.users)
            ListTile(
              key: ValueKey('user-${u.name}'),
              leading: Icon(u.active ? Icons.person : Icons.person_off_outlined),
              title: Text(u.name),
              subtitle: Text([
                u.role.label,
                if (u.pinHash.isEmpty) 'sem PIN',
                if (!u.active) 'desativado',
                if (store.currentUser == u) 'você',
              ].join(' · ')),
              onTap: () => _edit(context, u),
            ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'O que cada papel pode fazer',
            icon: Icons.rule,
            children: [
              for (final r in Role.values) ...[
                Text(r.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(r == Role.admin
                    ? 'Tudo (menos módulos e licença, que são do fornecedor).'
                    : Perm.values.where(r.perms.contains).map((p) => p.label).join(' · ')),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, AppUser? original) async {
    final store = StoreScope.read(context);
    final first = store.users.isEmpty;
    final u = original ??
        AppUser(id: newId(), name: '', role: first ? Role.admin : Role.producao);
    var name = u.name;
    var role = u.role;
    final pin = TextEditingController();
    var changePin = original == null;
    final ok = await showFormDialog<bool>(
      context: context,
      title: original == null ? 'Novo usuário' : 'Editar usuário',
      onSave: () {
        if (name.trim().isEmpty) {
          toast(context, 'Informe o nome.');
          return null;
        }
        final p = pin.text.trim();
        if (changePin && role != Role.producao && p.length < 4) {
          toast(context, 'PIN de 4 a 8 números (só Produção pode ficar sem PIN).');
          return null;
        }
        if (changePin && p.isNotEmpty && p.length < 4) {
          toast(context, 'PIN de 4 a 8 números.');
          return null;
        }
        return true;
      },
      body: (ctx, setS) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BoundField(
            label: 'Nome',
            value: name,
            capitalization: TextCapitalization.words,
            onChanged: (v) => name = v,
          ),
          const SizedBox(height: 12),
          Text('Papel', style: Theme.of(ctx).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final r in Role.values)
              ChoiceChip(
                label: Text(r.label),
                selected: role == r,
                onSelected: first ? null : (_) => setS(() => role = r),
              ),
          ]),
          const SizedBox(height: 12),
          if (!changePin)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setS(() => changePin = true),
                child: const Text('Trocar PIN'),
              ),
            )
          else
            pinField(pin,
                label: role == Role.producao ? 'PIN (opcional para Produção)' : 'PIN'),
          if (original != null) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ativo'),
              value: original.active,
              onChanged: (b) {
                try {
                  store.setUserActive(original, b);
                  setS(() {});
                } on AccessDenied catch (e) {
                  toast(ctx, e.message);
                }
              },
            ),
          ],
        ],
      ),
    );
    if (ok != true) return;
    final oldName = u.name, oldRole = u.role;
    u
      ..name = name.trim()
      ..role = role;
    try {
      await store.saveUser(u, newPin: changePin ? pin.text.trim() : null);
    } on AccessDenied catch (e) {
      u
        ..name = oldName
        ..role = oldRole;
      store.users.remove(original == null ? u : null);
      if (context.mounted) toast(context, e.message);
    }
  }
}
