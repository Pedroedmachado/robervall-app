import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/cash.dart';
import 'package:funilar/finance.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/main.dart';
import 'package:funilar/models.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/store.dart';
import 'package:funilar/team.dart';

/// Teste geral do aplicativo: o ciclo inteiro de um carro (estoque, equipe,
/// insumos, aprovação, conclusão, caixa, relatório da equipe, reabrir,
/// gravar e reabrir o app, excluir) e uma passada por todas as telas e
/// sub-abas em celular, tablet e computador.
void main() {
  Future<AppStore> openStore([Directory? dir]) async => AppStore.open(
      assumeLicense: License.full(),
      dir: dir ?? await Directory.systemTemp.createTemp('funilar_full'));

  /// Oficina com um carro completo: peça do estoque, reparo por peça,
  /// pintura, pintor por peça, funileiro terceirizado e insumo liberado.
  ({Claim claim, StockItem farol, StockItem lixa, Contact luan, Contact baiano})
      seedShop(AppStore store) {
    store.settings
      ..laborRates = {for (final l in LaborType.values) l.name: 100}
      ..paintRate = 90
      ..paintMaterialRate = 50;
    final farol = StockItem(
        name: 'Farol esquerdo',
        qty: 2,
        cost: 250,
        price: 390,
        shelf: 'B2',
        applications: [VehicleFit(make: 'Fiat', model: 'Argo', yearFrom: 2018, yearTo: 2024)]);
    final renegade = StockItem(
        name: 'Farol esquerdo',
        qty: 1,
        cost: 400,
        applications: [VehicleFit(make: 'Jeep', model: 'Renegade')]);
    final lixa = StockItem(
        kind: StockKind.material, name: 'Lixa P320', qty: 50, unit: 'folha', cost: 2);
    for (final s in [farol, renegade, lixa]) {
      store.upsertStock(s);
    }
    final luan = Contact(
        kind: ContactKind.funcionario, name: 'Luan', payType: PayType.porPeca, rate: 100);
    final baiano = Contact(
        kind: ContactKind.funcionario,
        name: 'Baiano',
        outsourced: true,
        service: OutsourcedService.funilaria,
        payType: PayType.empreita,
        rate: 500);
    store.upsertContact(luan);
    store.upsertContact(baiano);

    final c = store.newClaim()
      ..customerName = 'Ana Souza'
      ..vehicle.plate = 'XYZ-9A99'
      ..vehicle.brand = 'Fiat'
      ..vehicle.model = 'Argo Drive 1.0'
      ..vehicle.year = '2021'
      ..damages = {'capo': 2, 'parachoque_d': 1};
    final farolItem = BudgetItem(
        description: 'Farol esquerdo', op: ItemOp.troca, price: 390, laborHours: 1);
    c.items = [
      farolItem,
      BudgetItem(
          description: 'Porta dianteira esquerda',
          op: ItemOp.reparo,
          perPiece: true,
          piecePrice: 600,
          doRepair: true,
          doPaint: true),
      BudgetItem(description: 'Capô', op: ItemOp.pintura, paintHours: 2),
    ];
    // o estoque só oferece o farol que serve no carro (não o do Renegade)
    final offer = stockFor(store.stock, farolItem, c.vehicle);
    expect(offer.map((e) => e.id), [farol.id]);
    farolItem.stockId = farol.id;
    c.crew = [
      CrewMember(role: OutsourcedService.pintura, contactId: luan.id),
      CrewMember(role: OutsourcedService.funilaria, contactId: baiano.id),
    ];
    store.touch(c);
    store.issueSupply(c, lixa, 10, worker: luan);
    return (claim: c, farol: farol, lixa: lixa, luan: luan, baiano: baiano);
  }

  group('ciclo completo de um carro', () {
    test('orçamento → aprovado → concluído → caixa e equipe → reabrir → excluir',
        () async {
      final store = await openStore();
      final s = seedShop(store);
      final c = s.claim;
      CashEntry? profitEntry() =>
          store.cash.where((e) => e.id == 'lucro-${c.id}').firstOrNull;
      List<FinanceEntry> crewEntries() =>
          store.entries.where((e) => e.claimId == c.id && isCrewEntry(e)).toList();

      // aberto: nada sai do estoque e não há custo de equipe nem lucro
      expect(c.status, ClaimStatus.aberto);
      expect(s.farol.qty, 2);
      expect(crewEntries(), isEmpty);
      expect(profitEntry(), isNull);
      // insumo já saiu para o pintor
      expect(s.lixa.qty, 40);
      expect(c.supplies.single.workerName, 'Luan');
      expect(c.timeline.any((e) => e.text.contains('Insumo liberado')), isTrue);

      // aprovado: dá baixa da peça e lança a equipe no financeiro
      store.setStatus(c, ClaimStatus.aprovado, note: 'Seguradora');
      expect(c.approvedAt, isNotNull);
      expect(s.farol.qty, 1);
      expect(c.stockTaken.length, 1);
      expect(crewEntries().length, 2);
      final baianoCost = crewEntries().firstWhere((e) => e.contact == 'Baiano');
      expect(baianoCost.amount, 500);
      expect(crewEntries().firstWhere((e) => e.contact == 'Luan').amount,
          greaterThan(0));

      final j = jobCost(c, store.settings,
          entries: store.entries,
          contactById: store.contactById,
          stockById: store.stockById);
      expect(j.stockParts, 250);
      expect(j.supplies, 20);
      expect(j.crew, greaterThanOrEqualTo(500));
      expect(j.approved, greaterThan(j.total));

      // concluído: o lucro líquido entra no caixa
      store.setStatus(c, ClaimStatus.concluido);
      expect(c.concludedAt, isNotNull);
      expect(profitEntry(), isNotNull);
      expect(profitEntry()!.amount, closeTo(j.profit, .001));
      final now = DateTime.now();
      final month = Period.month(now.year, now.month);
      expect(summarizeCash(store.cash, month).entradas, closeTo(j.profit, .001));

      // relatório da equipe do mês
      final team = teamReport(
          claims: store.claims,
          contacts: store.contacts,
          settings: store.settings,
          period: month);
      final luan = team.firstWhere((r) => r.name == 'Luan');
      expect(luan.material, 20);
      expect(luan.cars.length, 1);
      final baiano = team.firstWhere((r) => r.name == 'Baiano');
      expect(baiano.pay, 500);
      expect(baiano.revenue, greaterThan(0));

      // devolveu o insumo: estoque volta e o lucro sobe na hora
      final before = profitEntry()!.amount;
      store.returnSupply(c, c.supplies.single);
      expect(s.lixa.qty, 50);
      expect(profitEntry()!.amount, closeTo(before + 20, .001));

      // mudou o valor do funcionário: o custo do carro acompanha
      s.baiano.rate = 700;
      store.upsertContact(s.baiano);
      expect(crewEntries().firstWhere((e) => e.contact == 'Baiano').amount, 700);
      expect(profitEntry()!.amount, closeTo(before + 20 - 200, .001));

      // reabriu: o lucro sai do caixa; voltou ao início: devolve a peça
      store.setStatus(c, ClaimStatus.emReparo);
      expect(profitEntry(), isNull);
      expect(s.farol.qty, 1);
      store.setStatus(c, ClaimStatus.aberto);
      expect(s.farol.qty, 2);
      expect(crewEntries(), isEmpty);

      // excluir com tudo lançado limpa estoque, equipe e caixa
      store.setStatus(c, ClaimStatus.entregue);
      expect(s.farol.qty, 1);
      expect(profitEntry(), isNotNull);
      await store.deleteClaim(c);
      expect(store.claims, isEmpty);
      expect(s.farol.qty, 2);
      expect(store.entries.where((e) => e.claimId == c.id), isEmpty);
      expect(store.cash.where((e) => e.claimId == c.id), isEmpty);
      store.dispose();
    });

    test('tudo é gravado e volta igual ao abrir o app de novo', () async {
      final dir = await Directory.systemTemp.createTemp('funilar_reabrir');
      final a = await openStore(dir);
      final s = seedShop(a);
      a.setStatus(s.claim, ClaimStatus.concluido);
      a.upsertCash(CashEntry(isIn: false, amount: 300, category: 'Energia'));
      a.upsertCatalog(CatalogItem(description: 'Para-lama', price: 450));
      a.settings.numberPrefix = 'OS';
      a.changed();
      await a.flush();
      a.dispose();

      final b = await openStore(dir);
      final c = b.claims.single;
      expect(c.number, s.claim.number);
      expect(c.status, ClaimStatus.concluido);
      expect(c.items.length, 3);
      expect(c.items[1].perPiece, isTrue);
      expect(c.crew.length, 2);
      expect(c.supplies.single.workerName, 'Luan');
      expect(c.stockTaken.length, 1);
      expect(b.stock.firstWhere((e) => e.id == s.farol.id).qty, 1);
      expect(b.stock.firstWhere((e) => e.id == s.lixa.id).qty, 40);
      expect(b.stock.firstWhere((e) => e.id == s.farol.id).applications.single.model,
          'Argo');
      expect(b.contactsOf(ContactKind.funcionario).length, 2);
      expect(b.cash.length, 2); // lucro + energia
      expect(b.entries.where(isCrewEntry).length, 2);
      expect(b.catalog.single.description, 'Para-lama');
      expect(b.settings.numberPrefix, 'OS');
      expect(b.settings.paintRate, 90);
      // reabrir não duplica lançamentos automáticos
      b.touch(c);
      expect(b.cash.length, 2);
      expect(b.entries.where(isCrewEntry).length, 2);
      b.dispose();
    });
  });

  group('cadastros, catálogo e ajustes (dados)', () {
    test('numeração, duplicar e excluir', () async {
      final store = await openStore();
      store.settings
        ..numberPrefix = 'OS'
        ..nextNumber = 7;
      final a = store.newClaim()
        ..customerName = 'Bia'
        ..items = [
          BudgetItem(description: 'Porta', op: ItemOp.troca, price: 900),
        ];
      store.touch(a);
      expect(a.number, 'OS-0007');
      store.setStatus(a, ClaimStatus.aprovado);
      final b = store.duplicate(a);
      expect(b.number, 'OS-0008');
      expect(b.status, ClaimStatus.aberto);
      expect(b.approvedAt, isNull);
      expect(b.items.single.id, isNot(a.items.single.id));
      expect(b.items.single.description, 'Porta');
      expect(store.claims.first, b);
      await store.deleteClaim(b);
      expect(store.claims, [a]);
      store.dispose();
    });

    test('contatos: salvar, ordenar, lembrar do sinistro e remover da equipe',
        () async {
      final store = await openStore();
      final z = Contact(kind: ContactKind.fornecedor, name: 'Zeca Peças');
      final a = Contact(kind: ContactKind.fornecedor, name: 'Auto Center');
      store.upsertContact(z);
      store.upsertContact(a);
      expect(store.contactsOf(ContactKind.fornecedor).map((e) => e.name),
          ['Auto Center', 'Zeca Peças']);

      final c = store.newClaim()
        ..customerName = 'Carla'
        ..insurerName = 'Porto'
        ..regulatorName = 'Perito João';
      store.rememberContactsFrom(c);
      store.rememberContactsFrom(c); // não duplica
      expect(store.contactsOf(ContactKind.cliente).length, 1);
      expect(store.contactsOf(ContactKind.seguradora).single.name, 'Porto');
      expect(store.contactsOf(ContactKind.regulador).single.name, 'Perito João');

      final w = Contact(kind: ContactKind.funcionario, name: 'Luan', rate: 80);
      store.upsertContact(w);
      c.crew = [CrewMember(contactId: w.id)];
      store.removeContact(w);
      expect(c.crew, isEmpty);
      expect(store.contactById(w.id), isNull);
      store.dispose();
    });

    test('catálogo: salvar em ordem e remover', () async {
      final store = await openStore();
      final p = CatalogItem(description: 'Para-choque', price: 800);
      final c = CatalogItem(
          description: 'Capô', op: ItemOp.reparo, perPiece: true, piecePrice: 350);
      store.upsertCatalog(p);
      store.upsertCatalog(c);
      expect(store.catalog.map((e) => e.description), ['Capô', 'Para-choque']);
      final back = CatalogItem.fromJson(c.toJson());
      expect(back.perPiece, isTrue);
      expect(back.piecePrice, 350);
      store.removeCatalog(p);
      expect(store.catalog.single, c);
      store.dispose();
    });
  });

  // ------------------------------------------------------------------ telas

  late AppStore store;

  Future<({Claim claim, StockItem farol, StockItem lixa, Contact luan, Contact baiano})>
      start(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    store = (await t.runAsync(openStore))!;
    final s = seedShop(store);
    store.setStatus(s.claim, ClaimStatus.concluido);
    store.upsertCash(CashEntry(
        isIn: true, amount: 1500, description: 'Venda balcão', category: 'Venda'));
    store.upsertCash(CashEntry(
        isIn: false,
        amount: 1200,
        planned: true,
        category: 'Aluguel',
        date: DateTime.now().add(const Duration(days: 5))));
    store.upsertCatalog(CatalogItem(description: 'Para-lama', price: 450));
    await t.pumpWidget(FunilarApp(store: store));
    await t.pumpAndSettle();
    return s;
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

  Future<void> segment(WidgetTester t, String label) => tap(
      t,
      find
          .descendant(
              of: find.byWidgetPredicate((w) => w is SegmentedButton),
              matching: find.text(label))
          .first);

  Finder field(String label) => find.widgetWithText(TextField, label);

  void itest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (t) async {
      await body(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 7));
    });
  }

  for (final (name, size) in [
    ('celular', const Size(390, 844)),
    ('tablet', const Size(820, 1180)),
    ('computador', const Size(1440, 900)),
  ]) {
    itest('passa por todas as telas e sub-abas com dados ($name)', (t) async {
      final s = await start(t, size);

      await tap(t, nav('Painel'));
      await tap(t, nav('Sinistros'));
      expect(find.text('XYZ-9A99'), findsWidgets);

      // Financeiro: Vendas (3 visões), Caixa (3 visões), Equipe
      await tap(t, nav('Financeiro'));
      for (final v in ['Gastos', 'Vendas', 'Consolidado']) {
        await segment(t, v);
      }
      await tab(t, 'Caixa');
      expect(find.text('Caixa do período'), findsOneWidget);
      for (final v in ['Entradas', 'Saídas', 'Consolidado']) {
        await segment(t, v);
      }
      expect(find.textContaining('Pagar em', skipOffstage: false), findsWidgets);
      await tab(t, 'Equipe');
      expect(find.text('Equipe no período'), findsOneWidget);
      expect(find.textContaining('Luan', skipOffstage: false), findsWidgets);
      expect(find.textContaining('Baiano', skipOffstage: false), findsWidgets);

      await tap(t, nav('Estoque'));
      expect(find.textContaining('Farol esquerdo', skipOffstage: false), findsWidgets);
      await tap(t, nav('Catálogo'));
      expect(find.text('Para-lama'), findsOneWidget);
      await tap(t, nav('Cadastros'));
      for (final k in ContactKind.values) {
        await tab(t, k.label);
      }
      expect(find.text('Luan'), findsOneWidget);
      await tap(t, nav('Ajustes'));

      // sinistro: todas as abas
      await tap(t, nav('Sinistros'));
      await tap(t, find.text('XYZ-9A99').first);
      for (final v in ['Dados', 'Avarias', 'Fotos', 'Orçamento', 'O.S.', 'Histórico']) {
        await tab(t, v);
      }
      expect(find.textContaining('Status: Concluído', skipOffstage: false), findsWidgets);
      await tab(t, 'O.S.');
      expect(find.text('Custo real da O.S.', skipOffstage: false), findsOneWidget);
      // pré-visualização do orçamento
      await tap(t, find.byTooltip('Ver orçamento'));
      expect(find.text('ORÇAMENTO'), findsOneWidget);
      expect(s.claim.items.length, 3);
    });
  }

  itest('O.S.: devolver insumo ao estoque pelo botão', (t) async {
    final s = await start(t, const Size(390, 844));
    await tap(t, nav('Sinistros'));
    await tap(t, find.text('XYZ-9A99').first);
    await tab(t, 'O.S.');
    expect(s.lixa.qty, 40);
    await tap(t, find.byTooltip('Devolver ao estoque'));
    expect(s.claim.supplies, isEmpty);
    expect(s.lixa.qty, 50);
    expect(find.byTooltip('Devolver ao estoque'), findsNothing);
  });

  itest('caixa: abrir lançamento, excluir e desfazer', (t) async {
    await start(t, const Size(390, 844));
    await tap(t, nav('Financeiro'));
    await tab(t, 'Caixa');
    final before = store.cash.length;
    await tap(t, find.text('Venda balcão'));
    await tap(t, find.text('Excluir lançamento'));
    expect(store.cash.length, before - 1);
    expect(find.text('Venda balcão'), findsNothing);
    await tap(t, find.text('Desfazer'));
    expect(store.cash.length, before);
    expect(find.text('Venda balcão'), findsOneWidget);
  });

  itest('cadastros: novo cliente pela tela e busca', (t) async {
    await start(t, const Size(390, 844));
    await tap(t, nav('Cadastros'));
    await tab(t, ContactKind.cliente.label);
    await tap(t, find.text('Novo'));
    await t.enterText(field('Nome'), 'Oficina Teste Ltda');
    await t.pumpAndSettle();
    await tap(t, find.text('Salvar'));
    expect(store.contactsOf(ContactKind.cliente).map((e) => e.name),
        contains('Oficina Teste Ltda'));
    expect(find.text('Oficina Teste Ltda'), findsOneWidget);
    await t.enterText(
        find.widgetWithText(TextField, 'Buscar por nome, telefone ou documento'),
        'zzz');
    await t.pumpAndSettle();
    expect(find.text('Oficina Teste Ltda'), findsNothing);
  });

  itest('catálogo: novo item pela tela', (t) async {
    await start(t, const Size(1440, 900));
    await tap(t, nav('Catálogo'));
    await tap(t, find.text('Novo'));
    await t.enterText(field('Peça'), 'Retrovisor direito');
    await t.enterText(field('Preço da peça'), '320');
    await t.pumpAndSettle();
    await tap(t, find.text('Salvar'));
    final it = store.catalog.firstWhere((e) => e.description == 'Retrovisor direito');
    expect(it.price, 320);
    expect(it.op, ItemOp.troca);
    expect(find.text('Retrovisor direito'), findsOneWidget);
  });

  itest('ajustes: tema escuro, horas no orçamento e mão de obra por peça',
      (t) async {
    final s = await start(t, const Size(1440, 900));
    await tap(t, nav('Ajustes'));
    await tap(t, find.text('Escuro'));
    expect(store.settings.themeMode, 'dark');
    expect(Theme.of(t.element(find.text('Ajustes').first)).brightness,
        Brightness.dark);

    // horas no orçamento: colunas de horas aparecem na pré-visualização
    final hours = store.settings.showHours;
    await tap(t, find.text('Mostrar horas no orçamento'));
    expect(store.settings.showHours, !hours);
    if (!store.settings.showHours) {
      await tap(t, find.text('Mostrar horas no orçamento'));
    }
    expect(store.settings.showHours, isTrue);

    // mão de obra por peça como padrão para itens novos
    await tap(t, find.text('Cobrar mão de obra por peça'));
    expect(store.settings.perPieceDefault, isTrue);

    await tap(t, nav('Sinistros'));
    await tap(t, find.text('XYZ-9A99').first);
    await tap(t, find.byTooltip('Ver orçamento'));
    expect(find.text('M.O. (h)', skipOffstage: false), findsWidgets);
    await t.pageBack();
    await t.pumpAndSettle();

    await tab(t, 'Orçamento');
    await tap(t, find.text('Novo item'));
    await t.enterText(find.widgetWithText(TextField, 'Peça'), 'Para-lama');
    await t.pumpAndSettle();
    expect(field('Horas de reparo'), findsNothing); // já abre por peça
    await t.enterText(field('Valor da mão de obra da peça'), '200');
    await t.pumpAndSettle();
    await tap(t, find.text('Salvar'));
    if (find.text('Agora não').evaluate().isNotEmpty) {
      await tap(t, find.text('Agora não'));
    }
    final it = s.claim.items.firstWhere((e) => e.description == 'Para-lama');
    expect(it.perPiece, isTrue);
    expect(it.piecePrice, 200);
  });
}
