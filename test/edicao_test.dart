import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/edition.dart';
import 'package:funilar/main.dart';
import 'package:funilar/models.dart';
import 'package:funilar/modules.dart';
import 'package:funilar/store.dart';
import 'package:funilar/updater.dart';

/// Cada sistema (Funilar completo, Orçamentação, Cadastros e Gestão) abre
/// só com os seus módulos e páginas, com nome, arquivos e repositório próprios.
void main() {
  tearDown(() => edition = Edition.completo);

  test('este repositório é o sistema certo', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^name: (\w+)', multiLine: true).firstMatch(pubspec)![1],
        appEdition.package);
  });

  const pageLabels = {
    AppPage.painel: 'Painel',
    AppPage.financeiro: 'Financeiro',
    AppPage.estoque: 'Estoque',
    AppPage.catalogo: 'Catálogo',
    AppPage.cadastros: 'Cadastros',
    AppPage.ajustes: 'Ajustes',
  };

  for (final e in Edition.values) {
    testWidgets('${e.title}: módulos, páginas e identidade', (t) async {
      edition = e;
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = (await t.runAsync(() async => AppStore.open(
          dir: await Directory.systemTemp.createTemp('fn_${e.name}'),
          device: 'FN-TESTE')))!;

      for (final m in Mod.values) {
        expect(gate.active(m), e.modules.contains(m), reason: '${e.name}: ${m.name}');
      }
      expect(windowsAsset, '${e.asset}-windows-x64.zip');
      expect(releasesPage, contains(e.repo));
      expect(store.toJson()['app'], e.package);

      await t.pumpWidget(FunilarApp(store: store));
      await t.pumpAndSettle();
      final rail = find.byType(NavigationRail);
      bool inMenu(String label) => find
          .descendant(of: rail, matching: find.text(label))
          .evaluate()
          .isNotEmpty;
      final hasMenu = rail.evaluate().isNotEmpty;
      for (final p in AppPage.values) {
        final label = p == AppPage.sinistros ? e.claimsLabel : pageLabels[p]!;
        if (hasMenu) {
          expect(inMenu(label), e.pages.contains(p), reason: '${e.name}: $label');
        }
      }
      expect(find.text(e.title.split(' ').last[0]), findsWidgets); // logo

      if (e.pages.contains(AppPage.sinistros)) {
        // abre um carro: aba O.S. só onde tem produção
        final c = store.newClaim()..vehicle.model = 'Argo';
        store.touch(c);
        await t.pumpAndSettle();
        final menu = find.descendant(of: rail, matching: find.text(e.claimsLabel));
        await t.tap(menu);
        await t.pumpAndSettle();
        await t.tap(find.textContaining('Argo').first);
        await t.pumpAndSettle();
        final tabs = find.byType(TabBar);
        bool tab(String s) => find
            .descendant(of: tabs, matching: find.textContaining(s))
            .evaluate()
            .isNotEmpty;
        expect(tab('Orçamento'), isTrue);
        expect(tab('O.S.'), e.modules.contains(Mod.producao));
        expect(tab('Avarias'), e.modules.contains(Mod.vistoria));
      } else {
        // sistema de cadastros: abre direto na lista de cadastros
        expect(find.text('Buscar por nome, telefone ou documento'), findsOneWidget);
        await t.tap(find.text('Novo'));
        await t.pumpAndSettle();
        await t.enterText(find.widgetWithText(TextField, 'Nome'), 'Cliente Teste');
        await t.pumpAndSettle();
        await t.tap(find.text('Salvar'));
        await t.pumpAndSettle();
        expect(store.contactsOf(ContactKind.cliente).single.name, 'Cliente Teste');
        // ajustes sem valor da hora nem orçamento
        await t.tap(find.descendant(of: rail, matching: find.text('Ajustes')));
        await t.pumpAndSettle();
        expect(find.text('Valor da hora'), findsNothing);
        expect(find.text('Dados da oficina (saem no PDF)'), findsOneWidget);
      }

      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 7));
    });
  }
}
