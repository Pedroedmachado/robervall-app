import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/modules.dart';
import 'package:funilar/format.dart';
import 'package:funilar/main.dart';
import 'package:funilar/models.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/store.dart';
import 'package:funilar/ui/damage_tab.dart';
import 'package:funilar/ui/finance_page.dart';


/// Cada teste toca num botão das telas de sinistro/orçamento e confere
/// se a ação realmente aconteceu nos dados e na tela.
void main() {
  late AppStore store;

  Future<void> start(WidgetTester tester,
      {Size size = const Size(390, 844), String? publicKey}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('funilar_it');
      return AppStore.open(
          assumeLicense: License.full(), dir: dir, publicKey: publicKey);
    }))!;
    await tester.pumpWidget(FunilarApp(store: store));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String label) => tap(
      tester,
      find
          .descendant(
              of: find.byType(TabBar), matching: find.textContaining(label))
          .first);

  /// Roda o teste e fecha o app no fim, para nenhum salvamento ficar pendente.
  void itest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (t) async {
      await body(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 7));
    });
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  /// Aba do menu principal (no celular o nome pode estar escondido).
  Finder nav(String label) {
    final dest = find.ancestor(
        of: find.text(label), matching: find.byType(NavigationDestination));
    return dest.evaluate().isNotEmpty ? dest.last : find.text(label).last;
  }

  Future<void> type(WidgetTester tester, Finder f, String text) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.enterText(f, text);
    await tester.pump();
  }

  Claim seed({String customer = 'Ana', String plate = 'XYZ-9A99'}) {
    final c = store.newClaim()
      ..customerName = customer
      ..vehicle.plate = plate
      ..vehicle.brand = 'Fiat'
      ..vehicle.model = 'Argo';
    store.changed();
    return c;
  }

  Future<void> openFirstClaim(WidgetTester tester) async {
    await tap(tester, nav('Sinistros'));
    await tap(tester, find.textContaining('Argo').first);
  }

  itest('novo sinistro: digitar placa atualiza título e lista', (t) async {
    await start(t);
    await tap(t, nav('Sinistros'));
    await tap(t, find.text('Novo'));
    expect(store.claims.length, 1);
    await type(t, field('Placa'), 'abc1d23');
    await type(t, field('Nome'), 'José da Silva');
    await settle(t);
    expect(store.claims.first.vehicle.plate, 'ABC-1D23');
    expect(find.textContaining('ABC-1D23'), findsWidgets); // título
    await tap(t, find.byTooltip('Voltar'));
    await settle(t);
    expect(find.text('ABC-1D23'), findsOneWidget); // cartão da lista
    expect(find.textContaining('José da Silva'), findsOneWidget);
    expect(store.contactsOf(ContactKind.cliente).length, 1);
    await settle(t);
  });

  itest('novo sinistro vazio é descartado ao voltar', (t) async {
    await start(t);
    await tap(t, nav('Sinistros'));
    await tap(t, find.text('Novo'));
    expect(store.claims.length, 1);
    await tap(t, find.byTooltip('Voltar'));
    await settle(t);
    expect(store.claims, isEmpty);
    expect(store.settings.nextNumber, 1);
    await settle(t);
  });

  itest('tipo de atendimento mostra seção da seguradora', (t) async {
    await start(t);
    final c = seed();
    await openFirstClaim(t);
    expect(find.text('Seguradora e regulação'), findsNothing);
    await tap(t, find.byType(DropdownMenu<ClaimType>));
    await tap(t, find.text('Seguradora').last);
    expect(c.type, ClaimType.seguradora);
    expect(find.text('Seguradora e regulação'), findsOneWidget);
    await settle(t);
  });

  itest('status: aprovar pede nome e registra', (t) async {
    await start(t);
    final c = seed();
    await openFirstClaim(t);
    await tap(t, find.text(ClaimStatus.aberto.label).first);
    await tap(t, find.text(ClaimStatus.aprovado.label).last);
    await type(t, find.byType(TextField).last, 'Perito João');
    await tap(t, find.text('OK'));
    expect(c.status, ClaimStatus.aprovado);
    expect(c.approvedBy, 'Perito João');
    expect(find.text(ClaimStatus.aprovado.label), findsWidgets);
    await settle(t);
  });

  itest('duplicar e excluir', (t) async {
    await start(t);
    seed();
    await openFirstClaim(t);
    await tap(t, find.byType(PopupMenuButton<String>));
    await tap(t, find.text('Duplicar orçamento'));
    expect(store.claims.length, 2);
    expect(find.textContaining(store.claims.first.number), findsWidgets);

    await tap(t, find.byType(PopupMenuButton<String>));
    await tap(t, find.text('Excluir'));
    await tap(t, find.widgetWithText(FilledButton, 'Excluir'));
    await settle(t);
    expect(store.claims.length, 1);
    await settle(t);
  });

  itest('orçamento: novo item, editar, aprovar, excluir e desfazer', (t) async {
    await start(t);
    final c = seed();
    await openFirstClaim(t);
    await tab(t, 'Orçamento');

    await tap(t, find.text('Novo item'));
    await type(t, find.widgetWithText(TextField, 'Peça'), 'Farol esquerdo');
    expect(field('Preço unitário da peça'), findsNothing); // só com troca
    await tap(t, find.text('Trocar a peça'));
    await type(t, field('Preço unitário da peça'), '450,50');
    await type(t, field('Horas de pintura'), '2');
    await tap(t, find.text('Salvar'));
    // troca do farol oferece complementos; aqui seguimos sem eles
    expect(find.text('Peças complementares'), findsOneWidget);
    await tap(t, find.text('Agora não'));
    expect(c.items.length, 1);
    expect(c.items.first.op, ItemOp.troca);
    expect(c.items.first.price, closeTo(450.5, 0.001));
    expect(find.text('Farol esquerdo'), findsOneWidget);
    // uma linha só, com as operações por extenso
    expect(find.text('Troca'), findsOneWidget);
    expect(find.text('Pintura 2 h'), findsOneWidget);

    // editar tocando no item
    await tap(t, find.text('Farol esquerdo'));
    await type(t, find.widgetWithText(TextField, 'Peça'), 'Farol direito');
    await t.pump();
    await tap(t, find.text('Salvar'));
    expect(c.items.first.description, 'Farol direito');

    // caixa de aprovado
    await tap(t, find.byType(Checkbox).first);
    expect(c.items.first.approved, isFalse);
    await tap(t, find.byType(Checkbox).first);
    expect(c.items.first.approved, isTrue);

    // excluir e desfazer
    await tap(t, find.byTooltip('Remover'));
    expect(c.items, isEmpty);
    await tap(t, find.text('Desfazer'));
    expect(c.items.length, 1);

    // o aviso de desfazer fecha sozinho e tem X para fechar
    await tap(t, find.byTooltip('Remover'));
    expect(find.text('Desfazer'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(find.text('Desfazer'), findsNothing);
    c.items.add(BudgetItem(description: 'Retrovisor', op: ItemOp.troca));
    store.changed();
    await settle(t);
    await tap(t, find.byTooltip('Remover'));
    expect(find.text('Desfazer'), findsOneWidget);
    await tap(t, find.byIcon(Icons.close).last);
    expect(find.text('Desfazer'), findsNothing);
    await settle(t);
  });

  itest('orçamento: item cobrado por peça (sem horas)', (t) async {
    await start(t);
    final c = seed();
    await openFirstClaim(t);
    await tab(t, 'Orçamento');
    await tap(t, find.text('Novo item'));
    await type(t, find.widgetWithText(TextField, 'Peça'), 'Porta dianteira');
    await tap(t, find.text('Por peça'));
    expect(field('Horas de reparo'), findsNothing);
    await tap(t, find.text('Pintura (P)'));
    await type(t, field('Valor da mão de obra da peça'), '350');
    await t.pumpAndSettle();
    await tap(t, find.text('Salvar'));
    if (find.text('Agora não').evaluate().isNotEmpty) {
      await tap(t, find.text('Agora não'));
    }
    final it = c.items.first;
    expect(it.description, 'Porta dianteira');
    expect(it.perPiece, isTrue);
    expect(it.piecePrice, 350);
    expect(it.hasPaint, isTrue);
    expect(it.op, ItemOp.reparo);
    expect(find.text('Por peça'), findsWidgets);
    await settle(t);
  });

  itest('estoque: insumo comprado em lata calcula o custo por ml', (t) async {
    await start(t);
    await tap(t, nav('Estoque'));
    await tap(t, find.text('Adicionar'));
    await tap(t, find.text('Insumo'));
    await type(t, field('Insumo (ex.: Lixa P320, Verniz HS 2x1)'), 'Thinner TH700 900ml');
    await tap(t, find.widgetWithText(ChoiceChip, 'ml'));
    await tap(t, find.text('Em embalagem'));
    expect(find.text('Cada lata tem'), findsOneWidget);
    await type(t, field('Preço da lata'), '41');
    await type(t, field('Quantidade de latas'), '2');
    await t.pumpAndSettle();
    expect(find.textContaining('1 lata = 900 ml'), findsOneWidget);
    expect(find.textContaining('Custo por ml: R\$ 0,0456'), findsOneWidget);
    await tap(t, find.text('Salvar'));
    final s = store.stock.single;
    expect(s.qty, 1800);
    expect(s.unit, 'ml');
    expect(s.cost, closeTo(41 / 900, 1e-9));
    expect(s.stockValue, closeTo(82, 1e-9));
    expect(find.text('1800 ml (2 latas)'), findsOneWidget);
    await settle(t);
  });

  itest('estoque: peça com aplicação e aviso de código repetido', (t) async {
    await start(t);
    store.upsertStock(StockItem(name: 'Farol esquerdo', partNumber: '5U0941005', qty: 1, sku: 'P-0001'));
    await settle(t);
    await tap(t, nav('Estoque'));
    await tap(t, find.text('Adicionar'));
    expect(find.text('1. Identificação'), findsOneWidget);
    await type(t, field('Peça (ex.: Farol esquerdo)'), 'Farol');
    await tap(t, find.widgetWithText(FilterChip, 'Esquerdo'));
    await t.pumpAndSettle();
    // mesmo OEM escrito com traço: avisa e não deixa salvar
    await type(t, field('Código OEM / referência original'), '5u0-941-005');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('aviso-repetido')), findsOneWidget);
    expect(find.textContaining('mesmo código OEM'), findsOneWidget);
    await tap(t, find.text('Adicionar veículo'));
    await type(t, field('Montadora'), 'vw');
    await type(t, field('Modelo'), 'Gol');
    await type(t, field('Ano de'), '2013');
    await type(t, field('Ano até'), '2016');
    await tap(t, find.text('Salvar'));
    expect(store.stock.length, 1); // bloqueado
    // somar na existente em vez de duplicar
    await tap(t, find.text('Somar 1'));
    expect(store.stock.length, 1);
    expect(store.stock.single.qty, 2);
    await settle(t);
  });

  itest('estoque: peça nova ganha código interno e aplicação', (t) async {
    await start(t);
    await tap(t, nav('Estoque'));
    await tap(t, find.text('Adicionar'));
    await type(t, field('Peça (ex.: Farol esquerdo)'), 'Lanterna traseira');
    await tap(t, find.widgetWithText(FilterChip, 'Direito'));
    await type(t, field('Código OEM / referência original'), '5U6945112');
    await tap(t, find.text('Adicionar veículo'));
    await type(t, field('Montadora'), 'vw');
    await type(t, field('Modelo'), 'Gol');
    await type(t, field('Ano de'), '2016');
    await type(t, field('Ano até'), '2013');
    await tap(t, find.text('Salvar'));
    expect(store.stock, isEmpty); // ano "de" maior que "até"
    await type(t, field('Ano de'), '2013');
    await type(t, field('Ano até'), '2016');
    await tap(t, find.text('Salvar'));
    final p = store.stock.single;
    expect(p.name, 'Lanterna traseira direita');
    expect(p.sku, 'P-0001');
    expect(p.applications.single.make, 'Volkswagen');
    expect(p.applications.single.label, 'Volkswagen Gol 2013–2016');
    await settle(t);
  });

  itest('estoque: cadastrar peça e usar no orçamento', (t) async {
    await start(t);
    final c = seed();
    await tap(t, nav('Estoque'));
    await tap(t, find.text('Adicionar'));
    await type(t, field('Peça (ex.: Farol esquerdo)'), 'Farol esquerdo');
    await type(t, field('Preço no orçamento (cada)'), '320');
    await tap(t, find.text('Salvar'));
    expect(store.stock.single.name, 'Farol esquerdo');
    expect(find.text('Farol esquerdo'), findsOneWidget);
    // só aparece no carro para o qual foi cadastrada
    store.stock.single.applications.add(VehicleFit(make: 'Fiat', model: 'Argo'));
    store.upsertStock(StockItem(name: 'Farol esquerdo', qty: 3,
        applications: [VehicleFit(make: 'Jeep', model: 'Renegade')]));

    c.items.add(BudgetItem(description: 'Farol esquerdo', op: ItemOp.troca));
    store.changed();
    await settle(t);
    await tap(t, nav('Sinistros'));
    await openFirstClaim(t);
    await tab(t, 'Orçamento');
    expect(find.text('Mercado Livre'), findsOneWidget);
    await tap(t, find.text('Tem no estoque (1)'));
    await tap(t, find.widgetWithText(FilledButton, 'Usar'));
    expect(c.items.single.stockId,
        store.stock.firstWhere((e) => e.applications.first.model == 'Argo').id);
    expect(c.items.single.price, 320);
    expect(find.text('Do estoque ✓'), findsOneWidget);

    store.setStatus(c, ClaimStatus.aprovado);
    await settle(t);
    expect(store.stock.firstWhere((e) => e.applications.first.model == 'Argo').qty, 0);
    expect(store.stock.firstWhere((e) => e.applications.first.model == 'Renegade').qty, 3);
    await settle(t);
  });

  itest('item: R&I, reparo e pintura juntos', (t) async {
    await start(t);
    final c = seed();
    await openFirstClaim(t);
    await tab(t, 'Orçamento');
    await tap(t, find.text('Novo item'));
    await type(t, find.widgetWithText(TextField, 'Peça'), 'Para-lama dianteiro esquerdo');
    await tap(t, find.text('Por peça'));
    await tap(t, find.text('Remoção e instalação (R&I)'));
    await tap(t, find.text('Pintura (P)'));
    await type(t, field('Valor da mão de obra da peça'), '450');
    await tap(t, find.text('Salvar'));
    if (find.text('Agora não').evaluate().isNotEmpty) {
      await tap(t, find.text('Agora não'));
    }
    final it = c.items.first;
    expect(it.removeInstall, isTrue);
    expect(it.alsoRepair, isTrue);
    expect(it.doPaint, isTrue);
    expect(opCode(it.op, it.labFlag, it.paintFlag,
            removeInstall: it.removeInstall, alsoRepair: it.alsoRepair),
        'R&I / R / P');
    await settle(t);
  });

  itest('avarias: pré-existente separado do sinistro e checklist', (t) async {
    await start(t);
    final c = seed();
    await openFirstClaim(t);
    await tab(t, 'Avarias');
    await tap(t, find.text('Pré-existente'));
    await tap(t, find.byTooltip('Capô'));
    expect(c.preDamages, {'capo': 1});
    expect(c.damages, isEmpty);
    await tap(t, find.text('Avaria do sinistro', skipOffstage: false));
    await tap(t, find.byTooltip('Capô'));
    expect(c.damages, {'capo': 1});
    await t.dragUntilVisible(find.text('Registrar agora'),
        find.byType(ListView).last, const Offset(0, -300));
    await t.pumpAndSettle();
    await tap(t, find.text('Registrar agora'));
    expect(c.reception.at, isNotNull);
    await tap(t, find.widgetWithText(ChoiceChip, '1/2'));
    await tap(t, find.widgetWithText(FilterChip, 'Estepe'));
    expect(c.reception.fuel, 2);
    expect(c.reception.items, {'Estepe'});
    await settle(t);
  });

  itest('O.S.: marcar tarefa e liberar insumo', (t) async {
    await start(t);
    final c = seed();
    store.upsertStock(StockItem(kind: StockKind.material, name: 'Thinner TH700', qty: 900, unit: 'ml', cost: 0.05));
    store.upsertContact(Contact(kind: ContactKind.funcionario, name: 'Luan', payType: PayType.porPeca, rate: 50));
    store.upsertContact(Contact(kind: ContactKind.funcionario, name: 'Baiano', outsourced: true, service: OutsourcedService.funilaria));
    c.crew = [CrewMember(role: OutsourcedService.pintura, contactId: store.contacts.firstWhere((e) => e.name == 'Luan').id)];
    c.items.add(BudgetItem(description: 'Porta', op: ItemOp.reparo, laborHours: 2));
    store.upsertStock(StockItem(
        kind: StockKind.material, name: 'Lixa P320', qty: 20, unit: 'folha', cost: 2));
    await settle(t);
    await openFirstClaim(t);
    await tab(t, 'O.S.');
    await tap(t, find.byKey(ValueKey('task-${c.items.single.id}')));
    expect(c.items.single.done, isTrue);
    await tap(t, find.text('Liberar insumo'));
    // busca do insumo
    await t.enterText(find.byKey(const ValueKey('busca-insumo')), 'thin');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('insumo-Thinner TH700')), findsOneWidget);
    expect(find.byKey(const ValueKey('insumo-Lixa P320')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('busca-insumo')), 'lixa');
    await t.pumpAndSettle();
    await tap(t, find.byKey(const ValueKey('insumo-Lixa P320')));
    expect(find.text('Selecionado: Lixa P320'), findsOneWidget);
    // lixa em folha: sai em pedaços de 1/4 ou 2/4 no taco
    expect(find.text('1/4 de folha'), findsOneWidget);
    await type(t, field('Quantos pedaços'), '5');
    await t.pumpAndSettle();
    expect(find.text('Sai do estoque: 1 e 1/4 folha'), findsOneWidget);
    await tap(t, find.widgetWithText(ChoiceChip, '2/4 no taco'));
    // quem recebe: a equipe do carro aparece primeiro
    await tap(t, find.byKey(const ValueKey('recebe-Luan')));
    expect(find.text('Sai do estoque: 2 e 1/2 folhas'), findsOneWidget);
    await tap(t, find.text('Salvar'));
    expect(c.supplies.single.qty, 2.5);
    expect(store.stock.firstWhere((e) => e.name == 'Lixa P320').qty, 17.5);
    expect(find.textContaining('Lixa P320 · 2 e 1/2 folhas'), findsOneWidget);
    expect(find.text('Total de insumos (1 saída)'), findsOneWidget);
    expect(c.supplies.single.workerName, 'Luan');
    expect(find.textContaining('para Luan'), findsOneWidget);
    expect(find.byKey(const ValueKey('total-insumos')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('total-insumos'))).data, money(5));
    expect(find.text('Custo real da O.S.', skipOffstage: false), findsOneWidget);
    await settle(t);
  });

  itest('usuários: produção não vê valores e insumo pede autorização', (t) async {
    await start(t);
    final c = seed();
    c.items.add(BudgetItem(description: 'Porta', op: ItemOp.reparo, laborHours: 2));
    store.upsertStock(StockItem(
        kind: StockKind.material, name: 'Lixa P320', qty: 20, unit: 'folha', cost: 2));
    await t.runAsync(() async {
      await store.saveUser(AppUser(id: 'a', name: 'Dono', role: Role.admin), newPin: '4321');
      await store.saveUser(AppUser(id: 'p', name: 'Zé', role: Role.producao), newPin: '');
    });
    store.logout();
    await settle(t);

    // login
    expect(find.text('Quem está usando?'), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('login-Zé')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(t);
    expect(store.currentUser?.name, 'Zé');
    expect(find.textContaining('sem valores'), findsOneWidget);
    expect(find.text('Financeiro'), findsNothing);
    expect(find.text('Ajustes'), findsNothing);
    expect(money(100), 'R\$ •••');

    // O.S. sem orçamento; insumo pede o PIN de quem pode liberar
    await tap(t, find.textContaining('Argo').first);
    expect(find.descendant(of: find.byType(TabBar), matching: find.textContaining('Orçamento')),
        findsNothing);
    await tab(t, 'O.S.');
    await tap(t, find.text('Liberar insumo'));
    expect(find.text('Autorização'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('pin-PIN')), '4321');
    await t.runAsync(() async {
      await t.tap(find.text('Autorizar'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(t);
    await tap(t, find.text('Salvar'));
    expect(c.supplies.single.qty, 0.25); // um pedaço de 1/4
    expect(store.stock.single.qty, 19.75);
    await tap(t, find.byTooltip('Voltar'));

    // troca de usuário
    await tap(t, find.text('Trocar usuário'));
    await tap(t, find.byKey(const ValueKey('login-Dono')));
    await t.enterText(find.byKey(const ValueKey('pin-PIN')), '4321');
    await t.runAsync(() async {
      await t.tap(find.text('Entrar'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(t);
    expect(store.currentUser?.name, 'Dono');
    expect(money(100), 'R\$ 100,00');
    await settle(t);
  });

  itest('orçamento: itens do catálogo, outros custos e desconto', (t) async {
    await start(t);
    final c = seed();
    await openFirstClaim(t);
    await tab(t, 'Orçamento');
    await tap(t, find.text('Do catálogo'));
    await tap(t, find.byType(CheckboxListTile).first);
    await tap(t, find.byType(CheckboxListTile).at(1));
    await tap(t, find.textContaining('Adicionar 2'));
    expect(c.items.length, 2);

    // o resumo fica depois da equipe do carro: rola até ele
    await t.dragUntilVisible(field('Outros custos (guincho…)'),
        find.byType(ListView).last, const Offset(0, -300));
    await t.pumpAndSettle();
    await type(t, field('Outros custos (guincho…)'), '200');
    await settle(t);
    expect(c.extraCosts, 200);
    await type(t, field('Desconto'), '10');
    await settle(t);
    expect(c.discountPct, 10);
    await settle(t);
  });

  itest('avarias: marcar no carro e gerar itens', (t) async {
    await start(t);
    final c = seed();
    await openFirstClaim(t);
    await tab(t, 'Avarias');
    await tap(t, find.byTooltip('Capô'));
    expect(c.damages['capo'], 1);
    await tap(t, find.byTooltip('Capô'));
    expect(c.damages['capo'], 2);
    final gen = find.text('Gerar itens no orçamento');
    await t.scrollUntilVisible(gen, 200,
        scrollable: find
            .descendant(
                of: find.byType(DamageTab), matching: find.byType(Scrollable))
            .first);
    await tap(t, gen);
    // uma linha só para o capô, com reparo e pintura
    expect(c.items.length, 1);
    expect(c.items.single.description, 'Capô');
    expect(c.items.single.laborHours, greaterThan(0));
    expect(c.items.single.paintHours, greaterThan(0));
    await tab(t, 'Orçamento');
    expect(find.textContaining('Reparo'), findsWidgets);
    expect(find.textContaining('Pintura'), findsWidgets);
    await settle(t);
  });

  itest('histórico: anotar acompanhamento', (t) async {
    await start(t);
    final c = seed();
    await openFirstClaim(t);
    await tab(t, 'Histórico');
    await type(t, find.byType(TextField).last, 'Peça chegou');
    await tap(t, find.byTooltip('Anotar'));
    expect(c.timeline.last.text, 'Peça chegou');
    expect(find.text('Peça chegou'), findsOneWidget);
    await settle(t);
  });

  itest('total no rodapé leva à aba Orçamento', (t) async {
    await start(t);
    seed();
    await openFirstClaim(t);
    await tap(t, find.text('Total '));
    expect(find.text('Novo item'), findsOneWidget);
    await settle(t);
  });

  itest('lista: busca, filtro de status e ordenação', (t) async {
    await start(t);
    seed(customer: 'Ana', plate: 'AAA-1A11');
    final b = seed(customer: 'Bruno', plate: 'BBB-2B22');
    store.setStatus(b, ClaimStatus.emReparo);
    await tap(t, nav('Sinistros'));
    expect(find.text('AAA-1A11'), findsOneWidget);
    expect(find.text('BBB-2B22'), findsOneWidget);

    await type(t, find.byType(TextField).first, 'bbb2');
    await settle(t);
    expect(find.text('AAA-1A11'), findsNothing);
    expect(find.text('BBB-2B22'), findsOneWidget);
    await type(t, find.byType(TextField).first, '');
    await settle(t);

    final chip = find.widgetWithText(FilterChip, ClaimStatus.emReparo.label);
    await t.scrollUntilVisible(chip, 150,
        scrollable: find
            .descendant(
                of: find.byKey(const Key('filtros')),
                matching: find.byType(Scrollable))
            .first);
    await tap(t, chip);
    expect(find.text('AAA-1A11'), findsNothing);
    expect(find.text('BBB-2B22'), findsOneWidget);

    await tap(t, find.byTooltip('Ordenar'));
    await tap(t, find.text('Maior valor'));
    await settle(t);
  });

  itest('desktop: novo item em diálogo e PDF', (t) async {
    await start(t, size: const Size(1366, 768));
    final c = seed();
    await openFirstClaim(t);
    await tab(t, 'Orçamento');
    await tap(t, find.text('Novo item'));
    await type(t, find.widgetWithText(TextField, 'Peça'), 'Grade');
    await type(t, field('Horas de reparo'), '1,5');
    await tap(t, find.text('Salvar'));
    expect(c.items.single.description, 'Grade');
    expect(c.items.single.op, ItemOp.reparo);

    // pré-visualização dentro do app, sem gerar PDF
    final before = c.timeline.length;
    await tap(t, find.byTooltip('Ver orçamento'));
    expect(find.text('ORÇAMENTO'), findsOneWidget);
    expect(find.text('Grade'), findsOneWidget);
    expect(find.text('Salvar PDF'), findsOneWidget);
    await tap(t, find.text('Sem valores'));
    expect(find.text('LAUDO DE VISTORIA'), findsOneWidget);
    expect(c.timeline.length, before); // nada de PDF gerado só por olhar
    await settle(t);
  });

  itest('financeiro: caixa com entrada, saída e pagamento previsto', (t) async {
    await start(t);
    seed();
    await settle(t);
    await tap(t, nav('Financeiro'));
    expect(find.text('Consolidado'), findsOneWidget); // Vendas: fluxo virou Consolidado
    await tap(t, find.descendant(of: find.byType(TabBar), matching: find.text('Caixa')));
    expect(find.text('Caixa do período'), findsOneWidget);

    await tap(t, find.text('Entrada'));
    await type(t, field('Valor'), '2000');
    await tap(t, find.widgetWithText(ChoiceChip, 'Dinheiro'));
    await tap(t, find.text('Salvar'));
    await tap(t, find.text('Saída'));
    await tap(t, find.widgetWithText(ChoiceChip, 'Energia'));
    await type(t, field('Valor'), '300');
    await tap(t, find.text('Salvar'));
    expect(store.cash.length, 2);
    expect(find.text(money(1700)), findsWidgets); // saldo

    await tap(t, find.text('Pagamento previsto'));
    await tap(t, find.widgetWithText(ChoiceChip, 'Aluguel'));
    await type(t, field('Valor'), '1200');
    await type(t, field('Repetir por quantos meses'), '3');
    await tap(t, find.text('Salvar'));
    expect(store.cash.where((e) => e.planned).length, 3);
    expect(find.textContaining('Pagar em'), findsWidgets);

    // pagou: confirma e vira saída do caixa
    await tap(t, find.byTooltip('Paguei').first);
    await tap(t, find.text('OK'));
    expect(store.cash.where((e) => e.planned).length, 2);
    expect(store.cash.where((e) => !e.planned && !e.isIn).length, 2);
    await settle(t);
  });

  itest('financeiro: lançar gasto fixo e ver o lucro', (t) async {
    await start(t);
    final c = seed();
    c.items.add(BudgetItem(op: ItemOp.servico, price: 5000));
    store.setStatus(c, ClaimStatus.aprovado);
    await settle(t);

    await tap(t, nav('Financeiro'));
    expect(find.text('Orçamentos fechados (1)'), findsOneWidget);
    expect(find.text(money(5000)), findsWidgets);

    await tap(t, find.text('Lançar gasto'));
    await tap(t, find.byType(DropdownMenu<ExpenseCategory>));
    await tap(t, find.text('Gastos fixos').last);
    await type(t, field('Descrição'), 'Aluguel');
    await type(t, field('Valor'), '1.500,00');
    await tap(t, find.text('Salvar'));
    expect(store.entries.single.amount, 1500);
    expect(store.entries.single.recurring, isTrue);
    expect(find.text('Lucro'), findsOneWidget);
    expect(find.text(money(3500)), findsWidgets);

    // aparece no fluxo de caixa e na lista de gastos
    expect(find.text('Aluguel'), findsOneWidget);
    await tap(t, find.text('Gastos').last);
    expect(find.text('Aluguel'), findsOneWidget);

    // próximo mês: o gasto fixo se repete e não há orçamento
    await tap(t, find.byTooltip('Próximo'));
    expect(find.text('Prejuízo'), findsOneWidget);
    expect(find.text(money(-1500)), findsWidgets);
    await settle(t);
  });

  itest('financeiro: anexar foto da nota preenche o lançamento sozinho', (t) async {
    await start(t);
    final img = (await t.runAsync(() async {
      final d = await Directory.systemTemp.createTemp('funilar_nota');
      final f = File('${d.path}/nota.jpg');
      await f.writeAsBytes([0, 1, 2, 3]);
      return f.path;
    }))!;
    debugPickReceipt = (_) async => img;
    debugReadReceipt = (_) async => const [
          'ART COLOR TINTAS',
          'RESERVA 0819365',
          '22/09/2026-17:19   VEND: 00010',
          'QTDE UNID   PRC UNIT   TOTAL',
          'VERNIZ A.SOLIDOS HS-2X1 13000 C/CAT.SKY',
          '4,00 QUART   89,00   356,00',
          'ACELERADOR SECAGEM RRA- 1LT SIKKENS',
          '1,00 LITRO   53,90   53,90',
          'TOTAL :   409,90',
          'A vista',
        ];
    addTearDown(() {
      debugPickReceipt = null;
      debugReadReceipt = null;
    });

    await tap(t, nav('Financeiro'));
    await tap(t, find.text('Lançar gasto'));
    final attach = find.text('Anexar foto da nota');
    await t.ensureVisible(attach);
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(attach);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();

    expect(find.textContaining('Nota lida'), findsOneWidget);
    expect(find.text('Trocar foto da nota'), findsOneWidget);
    expect(find.text('Reserva 0819365'), findsWidgets);
    await tap(t, find.text('Salvar'));
    final e = store.entries.single;
    expect(e.amount, closeTo(409.90, 0.001));
    expect(e.invoiceNumber, 'Reserva 0819365');
    expect(e.paymentMethod, 'À vista');
    expect(e.contact, 'Art Color Tintas');
    expect(e.category, ExpenseCategory.materiais);
    expect(e.date, DateTime(2026, 9, 22));
    expect(e.receiptFile, startsWith('nota_'));
    expect(e.notes, contains('Verniz'));
    await settle(t);
  });

  itest('financeiro: funcionário pago por peça e terceirizado', (t) async {
    await start(t);
    await tap(t, nav('Financeiro'));

    await tap(t, find.text('Lançar gasto'));
    await tap(t, find.byType(DropdownMenu<ExpenseCategory>));
    await tap(t, find.text('Funcionários e terceirizados').last);
    await tap(t, find.text('Por peça'));
    await type(t, field('Nº de peças'), '12');
    await type(t, field('Valor por peça'), '35');
    await settle(t);
    expect(find.textContaining('= ${money(420)}'), findsOneWidget);
    await type(t, field('Funcionário'), 'João pintor');
    await tap(t, find.text('Salvar'));
    final e = store.entries.single;
    expect(e.amount, 420);
    expect(e.payType, PayType.porPeca);
    expect(e.recurring, isFalse);

    await tap(t, find.text('Lançar gasto'));
    await tap(t, find.byType(DropdownMenu<ExpenseCategory>));
    await tap(t, find.text('Funcionários e terceirizados').last);
    await tap(t, find.text('Terceirizado'));
    expect(find.text('Salário'), findsNothing); // terceirizado não tem salário
    await type(t, field('Valor da empreita'), '800');
    await tap(t, find.text('Salvar'));
    final out = store.entries.firstWhere((x) => x.outsourced);
    expect(out.service, OutsourcedService.funilaria);
    expect(out.amount, 800);
    expect(find.text('Terceirizado · Funilaria'), findsWidgets);
    expect(find.text('Por peça'), findsOneWidget);
    await settle(t);
  });

  itest('troca de porta oferece os complementos e apaga junto', (t) async {
    await start(t);
    final c = seed();
    await openFirstClaim(t);
    await tab(t, 'Orçamento');
    await tap(t, find.text('Novo item'));
    await type(t, find.widgetWithText(TextField, 'Peça'), 'Porta dianteira esquerda');
    await tap(t, find.text('Trocar a peça'));
    await type(t, field('Preço unitário da peça'), '900');
    await tap(t, find.text('Salvar'));
    expect(find.text('Peças complementares'), findsOneWidget);
    expect(find.text('Máquina de vidro'), findsOneWidget);
    await tap(t, find.textContaining('Adicionar'));
    final porta = c.items.first;
    final kids = c.items.where((i) => i.parentId == porta.id).toList();
    expect(kids.length, greaterThan(8));
    expect(kids.every((k) => k.removeInstall), isTrue);
    expect(c.items.indexOf(kids.first), 1); // logo abaixo da porta

    // o botão de complementos avisa quando já está tudo lançado
    await tap(t, find.byTooltip('Peças complementares').first);
    expect(find.textContaining('já estão no orçamento'), findsOneWidget);

    // apagar a porta leva os complementos; desfazer devolve tudo
    await tap(t, find.byTooltip('Remover').first);
    expect(c.items, isEmpty);
    await tap(t, find.text('Desfazer'));
    expect(c.items.length, kids.length + 1);
    await settle(t);
  });

  itest('equipe do carro: pintor e martelinho com custo no financeiro', (t) async {
    await start(t);
    final c = seed();
    c.items = [
      BudgetItem(description: 'Capô', op: ItemOp.troca, price: 500, paintHours: 4),
      BudgetItem(description: 'Teto', op: ItemOp.pintura, paintHours: 2),
    ];
    store.upsertContact(Contact(
        kind: ContactKind.funcionario,
        name: 'João pintor',
        payType: PayType.porPeca,
        rate: 35));
    await settle(t);
    await openFirstClaim(t);
    await tab(t, 'Orçamento');
    await tap(t, find.widgetWithText(ActionChip, 'Pintor'));
    await tap(t, find.widgetWithText(ChoiceChip, 'João pintor · R\$ 35,00/peça'));
    expect(find.textContaining('Automático: 2 peças com pintura'), findsOneWidget);
    await tap(t, find.text('Salvar'));
    expect(c.crew.single.role, OutsourcedService.pintura);
    expect(find.text('Pintor · João pintor'), findsOneWidget);
    expect(find.text('Custo da equipe'), findsOneWidget);
    expect(find.text(money(70)), findsWidgets);
    expect(find.textContaining('quando o orçamento for fechado'), findsOneWidget);

    store.setStatus(c, ClaimStatus.aprovado);
    await settle(t);
    expect(store.entries.single.amount, 70);
    expect(find.textContaining('Lançado no Financeiro'), findsOneWidget);

    // martelinho de ouro: cadastra na hora e informa os amassados
    await tap(t, find.widgetWithText(ActionChip, 'Martelinho de ouro'));
    await tap(t, find.widgetWithText(ActionChip, 'Cadastrar novo'));
    await type(t, field('Nome'), 'Zé martelinho');
    await type(t, field('Valor por peça').last, '80');
    await tap(t, find.text('Salvar').last);
    await type(t, field('Nº de peças / amassados'), '3');
    await tap(t, find.text('Salvar').last);
    expect(c.crew.length, 2);
    final mart = store.entries.firstWhere((e) => e.contact == 'Zé martelinho');
    expect(mart.amount, 240);
    expect(mart.claimId, c.id);
    expect(mart.service, OutsourcedService.martelinho);
    await settle(t);
  });
}
