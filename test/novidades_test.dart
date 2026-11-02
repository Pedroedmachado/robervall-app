import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/calc.dart';
import 'package:funilar/finance.dart';
import 'package:funilar/format.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/main.dart';
import 'package:funilar/models.dart';
import 'package:funilar/seed.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/store.dart';
import 'package:funilar/ui/os_tab.dart';

/// Remoção e instalação com valor da hora próprio, preço mínimo por peça,
/// orçamento concluído travado, mapa de avarias acompanhando o orçamento,
/// estoque sem "de cliente" e insumo novo cadastrado de dentro da O.S.
void main() {
  group('cálculo', () {
    test('R&I tem horas e valor da hora próprios e aparece nos totais', () {
      final s = Settings(laborRates: {for (final l in LaborType.values) l.name: 100})
        ..riRate = 60
        ..paintRate = 90
        ..paintMaterialRate = 50;
      final it = BudgetItem(
          description: 'Para-lama',
          op: ItemOp.reparo,
          removeInstall: true,
          alsoRepair: true,
          riHours: 1.5,
          laborHours: 2,
          paintHours: 1);
      final v = itemValues(it, s);
      expect(v.ri, 90);
      expect(v.labor, 200);
      expect(v.total, 90 + 200 + 90 + 50);
      final c = Claim(number: 'X')..items = [it];
      final t = computeTotals(c, s);
      expect(t.ri, 90);
      expect(t.riHours, 1.5);
      expect(t.total, 430);
      // ida e volta
      expect(BudgetItem.fromJson(it.toJson()).riHours, 1.5);
      expect(Settings.fromJson(s.toJson()).riRate, 60);
    });

    test('versão antiga: horas de R&I migram e o valor de R&I vem da funilaria', () {
      final old = BudgetItem.fromJson({
        'description': 'Forro da porta',
        'op': 'reparo',
        'laborHours': 0.5,
        'ri': true,
      });
      expect(old.riHours, 0.5);
      expect(old.laborHours, 0);
      expect(old.hasLabor, isTrue);
      final s = Settings.fromJson({
        'laborRates': {'funilaria': 95}
      });
      expect(s.riRate, 95);
      final cat = CatalogItem.fromJson(
          {'description': 'Forro', 'op': 'reparo', 'laborHours': 0.7, 'ri': true});
      expect(cat.riHours, 0.7);
      expect(cat.toBudgetItem().riHours, 0.7);
    });

    test('preço mínimo por peça soma as funções marcadas', () {
      final s = Settings()
        ..pieceMin = {
          'funilaria': 150,
          'mecanica': 200,
          Settings.pieceMinPaint: 250,
          Settings.pieceMinRi: 80,
        };
      BudgetItem p(
              {ItemOp op = ItemOp.reparo,
              bool ri = false,
              bool rr = false,
              bool paint = false,
              bool repair = true,
              LaborType lt = LaborType.funilaria}) =>
          BudgetItem(
              op: op,
              perPiece: true,
              removeInstall: ri,
              alsoRepair: rr,
              doPaint: paint,
              doRepair: repair,
              laborType: lt);
      expect(pieceMinimum(p(), s), 150);
      expect(pieceMinimum(p(paint: true), s), 400);
      expect(pieceMinimum(p(ri: true), s), 80);
      expect(pieceMinimum(p(ri: true, rr: true, paint: true), s), 480);
      expect(pieceMinimum(p(lt: LaborType.mecanica), s), 200);
      expect(pieceMinimum(p(op: ItemOp.troca), s), 80); // tirar e colocar
      expect(pieceMinimum(p(repair: false, paint: true), s), 250);
      expect(pieceMinimum(BudgetItem(op: ItemOp.reparo, laborHours: 2), s), 0);
      expect(Settings.fromJson(s.toJson()).minFor(Settings.pieceMinPaint), 250);
    });

    test('peça removida desmarca a avaria do mapa (se não sobrar outra peça dela)', () {
      final capo = BudgetItem(description: 'Capô', op: ItemOp.pintura, region: 'capo');
      final capoReparo = BudgetItem(description: 'Capô', op: ItemOp.reparo);
      final para = BudgetItem(description: 'Para-choque dianteiro', region: 'parachoque_d');
      final c = Claim(number: 'X')
        ..damages = {'capo': 2, 'parachoque_d': 3, 'teto': 1}
        ..items = [capo, capoReparo, para];
      c.items.remove(para);
      expect(unmarkDamagesFor(c, [para]), {'parachoque_d': 3});
      expect(c.damages.keys, unorderedEquals(['capo', 'teto']));
      c.items.remove(capo);
      expect(unmarkDamagesFor(c, [capo]), isEmpty); // ainda tem o reparo do capô
      c.items.remove(capoReparo);
      expect(unmarkDamagesFor(c, [capoReparo]), {'capo': 2});
      expect(c.damages.keys, ['teto']); // avaria sem peça removida fica
    });

    test('mapa de avarias: só a pesada (3) vira troca; leve e média são reparo', () {
      final r = regionById('parachoque_d')!;
      final ops = {for (final (_, op) in r.suggestions) op};
      final leve = itemForDamage('Para-choque dianteiro', ops, 1, r.id);
      expect(leve.op, isNot(ItemOp.troca));
      expect(leve.laborHours, greaterThan(0)); // reparo
      expect(leve.paintHours, greaterThan(0)); // e pintura
      expect(opCode(leve.op, leve.labFlag, leve.paintFlag), 'R / P');
      final media = itemForDamage('Para-choque dianteiro', ops, 2, r.id);
      expect(media.op, isNot(ItemOp.troca));
      expect(media.laborHours, greaterThan(leve.laborHours));
      final pesada = itemForDamage('Para-choque dianteiro', ops, 3, r.id);
      expect(pesada.op, ItemOp.troca);
      // farol leve: reparo, não troca
      expect(itemForDamage('Farol esquerdo', {ItemOp.troca}, 1, 'farol_e').op,
          ItemOp.reparo);
      expect(itemForDamage('Farol esquerdo', {ItemOp.troca}, 3, 'farol_e').op,
          ItemOp.troca);
    });

    test('orçamento concluído ou entregue fica travado', () {
      final c = Claim(number: 'X');
      for (final st in ClaimStatus.values) {
        c.status = st;
        expect(budgetLocked(c),
            st == ClaimStatus.concluido || st == ClaimStatus.entregue, reason: st.name);
      }
    });
  });

  // ------------------------------------------------------------------ telas

  late AppStore store;

  Future<void> start(WidgetTester t, {Size size = const Size(390, 844)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    store = (await t.runAsync(() async => AppStore.open(
        assumeLicense: License.full(),
        dir: await Directory.systemTemp.createTemp('fn_novo'))))!;
    await t.pumpWidget(FunilarApp(store: store));
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Finder nav(String label) {
    final dest = find.ancestor(
        of: find.text(label), matching: find.byType(NavigationDestination));
    return dest.evaluate().isNotEmpty ? dest.last : find.text(label).last;
  }

  Future<void> tab(WidgetTester t, String label) => tap(
      t,
      find
          .descendant(of: find.byType(TabBar), matching: find.textContaining(label))
          .first);

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> type(WidgetTester t, Finder f, String text) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.enterText(f, text);
    await t.pumpAndSettle();
  }

  void itest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (t) async {
      await body(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 7));
    });
  }

  Claim seed() {
    final c = store.newClaim()
      ..customerName = 'Ana'
      ..vehicle.plate = 'XYZ-9A99'
      ..vehicle.brand = 'Fiat'
      ..vehicle.model = 'Argo';
    store.changed();
    return c;
  }

  Future<void> openClaim(WidgetTester t) async {
    await tap(t, nav('Sinistros'));
    await tap(t, find.textContaining('Argo').first);
  }

  itest('orçamento concluído: não dá para adicionar, editar nem excluir', (t) async {
    await start(t);
    final c = seed()
      ..items = [BudgetItem(description: 'Para-choque', op: ItemOp.troca, price: 900)];
    store.setStatus(c, ClaimStatus.concluido);
    await t.pumpAndSettle();
    await openClaim(t);
    await tab(t, 'Orçamento');
    expect(find.byKey(const ValueKey('orcamento-travado')), findsOneWidget);
    expect(find.text('Novo item'), findsNothing);
    expect(find.text('Do catálogo'), findsNothing);
    expect(find.byTooltip('Remover'), findsNothing);
    await tap(t, find.text('Para-choque'));
    expect(find.text('Editar item'), findsNothing); // não abre o editor
    expect(find.text(budgetLockedMsg), findsWidgets);
    expect(c.items.single.approved, isTrue);

    // reabriu: volta a editar
    store.setStatus(c, ClaimStatus.emReparo);
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('orcamento-travado')), findsNothing);
    expect(find.text('Novo item'), findsOneWidget);
  });

  itest('excluir a peça desmarca a avaria no mapa; desfazer volta as duas', (t) async {
    await start(t);
    final c = seed()
      ..damages = {'capo': 2}
      ..items = [BudgetItem(description: 'Capô', op: ItemOp.pintura, paintHours: 3, region: 'capo')];
    store.changed();
    await openClaim(t);
    expect(find.textContaining('Avarias (1)'), findsOneWidget);
    await tab(t, 'Orçamento');
    await tap(t, find.byTooltip('Remover'));
    expect(c.items, isEmpty);
    expect(c.damages, isEmpty);
    expect(find.textContaining('Avarias (0)'), findsOneWidget);
    await tap(t, find.text('Desfazer'));
    expect(c.items.length, 1);
    expect(c.damages, {'capo': 2});
  });

  itest('valor da hora de R&I: horas próprias e linha no orçamento', (t) async {
    await start(t, size: const Size(1366, 900));
    store.settings.riRate = 70;
    final c = seed();
    await tap(t, nav('Ajustes'));
    expect(find.text('Remoção e instalação (R&I)'), findsOneWidget);
    await openClaim(t);
    await tab(t, 'Orçamento');
    await tap(t, find.text('Novo item'));
    await type(t, find.widgetWithText(TextField, 'Peça'), 'Forro da porta');
    await tap(t, find.text('Remoção e instalação (R&I)'));
    await tap(t, find.text('Reparo (R)')); // só R&I
    expect(field('Horas de reparo'), findsNothing);
    await type(t, field('Horas de remoção e instalação'), '2');
    // pintura por horas: marca o "P" e aparecem as horas de pintura
    expect(field('Horas de pintura'), findsNothing);
    await tap(t, find.text('Pintura (P)'));
    await type(t, field('Horas de pintura'), '1');
    await tap(t, find.text('Pintura (P)'));
    expect(field('Horas de pintura'), findsNothing); // desmarcou: some e zera
    await tap(t, find.text('Salvar'));
    if (find.text('Agora não').evaluate().isNotEmpty) {
      await tap(t, find.text('Agora não'));
    }
    final it = c.items.single;
    expect(it.removeInstall, isTrue);
    expect(it.riHours, 2);
    expect(it.laborHours, 0);
    expect(itemValues(it, store.settings).ri, 140);
    expect(find.textContaining('Remoção e instalação (2'), findsOneWidget);
  });

  itest('mão de obra por peça: preço mínimo por função, sem preço por hora', (t) async {
    await start(t, size: const Size(1366, 900));
    final c = seed();
    await tap(t, nav('Ajustes'));
    expect(find.text('Valor da hora'), findsOneWidget);
    expect(find.text('Preço mínimo por peça'), findsNothing);
    await tap(t, find.text('Cobrar mão de obra por peça'));
    expect(find.text('Preço mínimo por peça'), findsOneWidget);
    expect(find.text('Valor da hora'), findsNothing);
    for (final l in ['Funilaria', 'Mecânica', 'Elétrica', 'Tapeçaria', 'Vidraçaria', 'Pintura', 'Remoção e instalação']) {
      expect(find.descendant(of: find.byType(TextField), matching: find.text(l)), findsOneWidget,
          reason: l);
    }
    Finder minField(String k) => find.descendant(
        of: find.byKey(ValueKey('min-$k')), matching: find.byType(TextField));
    await type(t, minField('funilaria'), '150');
    await type(t, minField('pintura'), '250');
    expect(store.settings.minFor('funilaria'), 150);
    expect(store.settings.minFor('pintura'), 250);

    await openClaim(t);
    await tab(t, 'Orçamento');
    await tap(t, find.text('Novo item'));
    expect(find.text('Por horas'), findsNothing); // sem cobrança por hora
    await type(t, find.widgetWithText(TextField, 'Peça'), 'Porta dianteira');
    await tap(t, find.text('Pintura (P)'));
    // já abre com o mínimo de reparo + pintura
    expect(find.text('Preço mínimo: ${money(400)}'), findsOneWidget);
    await type(t, field('Valor da mão de obra da peça'), '300');
    expect(find.text('Abaixo do mínimo: ${money(400)}'), findsOneWidget);
    await tap(t, find.text('Salvar'));
    expect(c.items, isEmpty); // não aceita abaixo do mínimo
    await type(t, field('Valor da mão de obra da peça'), '450');
    await tap(t, find.text('Salvar'));
    if (find.text('Agora não').evaluate().isNotEmpty) {
      await tap(t, find.text('Agora não'));
    }
    expect(c.items.single.perPiece, isTrue);
    expect(c.items.single.piecePrice, 450);
  });

  itest('estoque: sem a opção "do cliente"', (t) async {
    await start(t);
    await tap(t, nav('Estoque'));
    expect(find.text('De clientes'), findsNothing);
    await tap(t, find.text('Adicionar'));
    expect(find.text('Peça'), findsWidgets);
    expect(find.text('Insumo'), findsWidgets);
    expect(find.text('Do cliente'), findsNothing);
  });

  itest('O.S.: adicionar insumo novo na hora de liberar', (t) async {
    await start(t);
    final c = seed()..items = [BudgetItem(description: 'Porta', op: ItemOp.reparo, laborHours: 2)];
    store.upsertStock(StockItem(kind: StockKind.material, name: 'Lixa P320', qty: 20, unit: 'folha', cost: 2));
    store.changed();
    await t.pumpAndSettle();
    await openClaim(t);
    await tab(t, 'O.S.');
    await t.dragUntilVisible(
        find.text('Liberar insumo'),
        find.descendant(of: find.byType(OsTab), matching: find.byType(Scrollable)).first,
        const Offset(0, -250));
    await t.pumpAndSettle();
    await tap(t, find.text('Liberar insumo'));
    await tap(t, find.byKey(const ValueKey('adicionar-insumo')));
    await type(t, field('Insumo (ex.: Lixa P320, Verniz HS 2x1)'), 'Massa poliéster');
    await tap(t, find.text('Salvar').last);
    expect(store.stock.any((e) => e.name == 'Massa poliéster' && e.kind == StockKind.material),
        isTrue);
    expect(find.text('Selecionado: Massa poliéster'), findsOneWidget);
    await tap(t, find.text('Salvar').last);
    expect(c.supplies.single.name, 'Massa poliéster');
  });

  itest('O.S.: sem insumo no estoque já pede o primeiro cadastro', (t) async {
    await start(t);
    final c = seed();
    store.changed();
    await t.pumpAndSettle();
    await openClaim(t);
    await tab(t, 'O.S.');
    await t.dragUntilVisible(
        find.text('Liberar insumo'),
        find.descendant(of: find.byType(OsTab), matching: find.byType(Scrollable)).first,
        const Offset(0, -250));
    await t.pumpAndSettle();
    await tap(t, find.text('Liberar insumo'));
    expect(find.text('Novo no estoque'), findsOneWidget);
    await type(t, field('Insumo (ex.: Lixa P320, Verniz HS 2x1)'), 'Primer PU');
    await tap(t, find.text('Salvar').last);
    expect(find.text('Liberar insumo'), findsWidgets);
    expect(find.text('Selecionado: Primer PU'), findsOneWidget);
    await tap(t, find.text('Salvar').last);
    expect(c.supplies.single.name, 'Primer PU');
  });
}
