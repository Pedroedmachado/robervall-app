import 'package:flutter/material.dart';

import 'access.dart';
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
  int _index = 0;

  static const _dest = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard, 'Painel'),
    (Icons.car_crash_outlined, Icons.car_crash, 'Sinistros'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Financeiro'),
    (Icons.warehouse_outlined, Icons.warehouse, 'Estoque'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Catálogo'),
    (Icons.contacts_outlined, Icons.contacts, 'Cadastros'),
    (Icons.settings_outlined, Icons.settings, 'Ajustes'),
  ];

  void go(int i) => setState(() => _index = i);

  /// No modo produção só aparecem Sinistros e Estoque (sem valores) e um
  /// botão para o gestor destravar.
  static const _productionPages = [1, 3];

  Widget _page() {
    switch (_index) {
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
    if (store.settings.productionMode) return _production(context);
    final wide = isWide(context);
    final page = KeyedSubtree(key: ValueKey(_index), child: _page());
    if (!wide) {
      return Scaffold(
        body: page,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: go,
          // 7 abas: em telas estreitas mostra o nome só da aba aberta
          labelBehavior: MediaQuery.sizeOf(context).width < 480
              ? NavigationDestinationLabelBehavior.onlyShowSelected
              : NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final d in _dest)
              NavigationDestination(
                  icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
          ],
        ),
      );
    }
    final t = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: go,
            extended: MediaQuery.sizeOf(context).width >= 1200,
            minExtendedWidth: 200,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _Logo(color: t.colorScheme.primary),
            ),
            destinations: [
              for (final d in _dest)
                NavigationRailDestination(
                  icon: Icon(d.$1),
                  selectedIcon: Icon(d.$2),
                  label: Text(d.$3),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: page),
        ],
      ),
    );
  }
}

extension on _AppShellState {
  Widget _production(BuildContext context) {
    if (!_AppShellState._productionPages.contains(_index)) _index = 1;
    final sel = _AppShellState._productionPages.indexOf(_index);
    final page = KeyedSubtree(key: ValueKey('p$_index'), child: _page());
    final t = Theme.of(context);
    return Scaffold(
      body: Column(children: [
        Material(
          color: t.colorScheme.tertiaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                Icon(Icons.precision_manufacturing_outlined,
                    size: 18, color: t.colorScheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Modo produção · sem valores',
                      style: TextStyle(
                          color: t.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  onPressed: () => leaveProductionMode(context),
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Gestor'),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
              context: context, removeTop: true, child: page),
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: sel,
        onDestinationSelected: (i) => go(_AppShellState._productionPages[i]),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment),
              label: 'Ordens de serviço'),
          NavigationDestination(
              icon: Icon(Icons.warehouse_outlined),
              selectedIcon: Icon(Icons.warehouse),
              label: 'Estoque'),
        ],
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
