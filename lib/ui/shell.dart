import 'package:flutter/material.dart';

import '../modules.dart';
import 'license_ui.dart';
import 'users_ui.dart';
import 'catalog_page.dart';
import 'claims_page.dart';
import 'contacts_page.dart';
import 'dashboard_page.dart';
import 'finance_page.dart';
import 'settings_page.dart';
import 'stock_page.dart';
import '../theme.dart';
import 'widgets.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _page = 1; // começa em Sinistros quando o Painel não aparece

  static const _dest = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard, 'Painel'),
    (Icons.car_crash_outlined, Icons.car_crash, 'Sinistros'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Financeiro'),
    (Icons.warehouse_outlined, Icons.warehouse, 'Estoque'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Catálogo'),
    (Icons.contacts_outlined, Icons.contacts, 'Cadastros'),
    (Icons.settings_outlined, Icons.settings, 'Ajustes'),
  ];

  bool _initDone = false;

  /// Abas que este usuário vê, conforme os módulos ativos e o papel.
  List<int> _visible() => [
        if (gate.roleCan(Perm.valoresVer)) 0,
        1,
        if (gate.active(Mod.financeiro) && gate.roleCan(Perm.financeiroVer)) 2,
        if (gate.active(Mod.estoque) && gate.roleCan(Perm.estoqueVer)) 3,
        if (gate.roleCan(Perm.orcamentoEditar)) 4,
        if (gate.roleCan(Perm.cadastrosEditar)) 5,
        if (gate.roleCan(Perm.ajustes)) 6,
      ];

  void go(int page) => setState(() => _page = page);

  Widget _pageWidget(int i) {
    switch (i) {
      case 0:
        return DashboardPage(
            onOpenClaims: () => go(1), onOpenFinance: () => go(2));
      case 1:
        return const ClaimsPage();
      case 2:
        return const FinancePage();
      case 3:
        return const StockPage();
      case 4:
        return const CatalogPage();
      case 5:
        return const ContactsPage();
      default:
        return const SettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (store.needsLogin) return const LoginPage();
    final visible = _visible();
    if (!_initDone) {
      _initDone = true;
      _page = visible.first;
    }
    if (!visible.contains(_page)) _page = visible.contains(1) ? 1 : visible.first;
    final sel = visible.indexOf(_page);
    final wide = isWide(context);
    final page = KeyedSubtree(key: ValueKey(_page), child: _pageWidget(_page));
    final body = Column(children: [
      const _AccessBar(),
      Expanded(
        child: MediaQuery.removePadding(
            context: context,
            removeTop: gate.readOnly || store.activeUsers.length > 1,
            child: page),
      ),
    ]);
    if (!wide) {
      return Scaffold(
        body: body,
        bottomNavigationBar: visible.length < 2
            ? null
            : NavigationBar(
                selectedIndex: sel,
                onDestinationSelected: (i) => go(visible[i]),
                labelBehavior: MediaQuery.sizeOf(context).width < 480 &&
                        visible.length > 4
                    ? NavigationDestinationLabelBehavior.onlyShowSelected
                    : NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  for (final i in visible)
                    NavigationDestination(
                        icon: Icon(_dest[i].$1),
                        selectedIcon: Icon(_dest[i].$2),
                        label: _dest[i].$3),
                ],
              ),
      );
    }
    final t = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          if (visible.length >= 2)
            NavigationRail(
              selectedIndex: sel,
              onDestinationSelected: (i) => go(visible[i]),
              extended: MediaQuery.sizeOf(context).width >= 1200,
              minExtendedWidth: 200,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _Logo(color: t.colorScheme.primary),
              ),
              destinations: [
                for (final i in visible)
                  NavigationRailDestination(
                    icon: Icon(_dest[i].$1),
                    selectedIcon: Icon(_dest[i].$2),
                    label: Text(_dest[i].$3),
                  ),
              ],
            ),
          if (visible.length >= 2) const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Faixa do topo: licença inválida (só consulta) e usuário logado.
class _AccessBar extends StatelessWidget {
  const _AccessBar();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final multi = store.activeUsers.length > 1;
    if (!gate.readOnly && !multi) return const SizedBox.shrink();
    return Material(
      color: gate.readOnly ? t.colorScheme.errorContainer : t.colorScheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Column(children: [
            if (gate.readOnly)
              Row(children: [
                Icon(Icons.lock_outline, size: 18, color: t.colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${store.license.status.label} · somente consulta',
                      style: TextStyle(
                          color: t.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () => showInstallLicense(context),
                  child: const Text('Instalar licença'),
                ),
              ]),
            if (multi)
              Row(children: [
                Icon(Icons.person_outline, size: 18, color: t.colorScheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${store.currentUser?.name ?? ''} · ${store.currentUser?.role.label ?? ''}${gate.can(Perm.valoresVer) ? '' : ' · sem valores'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: t.colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: store.logout,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Trocar usuário'),
                ),
              ]),
          ]),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: const Text(
        'F',
        style: TextStyle(
            color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
      ),
    );
  }
}
