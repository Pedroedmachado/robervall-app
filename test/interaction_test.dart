import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/format.dart';
import 'package:funilar/main.dart';
import 'package:funilar/models.dart';
import 'package:funilar/store.dart';
import 'package:funilar/ui/damage_tab.dart';

/// Cada teste toca num botão das telas de sinistro/orçamento e confere
/// se a ação realmente aconteceu nos dados e na tela.
void main() {
  late AppStore store;

  Future<void> start(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('funilar_it');
      return AppStore.open(dir: dir);
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
    await tap(tester, find.text('Sinistros').last);
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
}
