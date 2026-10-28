import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Finder field(String label) => find.widgetWithText(TextField, label);

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

  testWidgets('novo sinistro: digitar placa atualiza título e lista', (t) async {
    await start(t);
    await tap(t, find.text('Sinistros').last);
    await tap(t, find.text('Novo'));
    expect(store.claims.length, 1);
    await type(t, field('Placa'), 'abc1d23');
    await type(t, field('Nome'), 'José da Silva');
    await settle(t);
    expect(store.claims.first.vehicle.plate, 'ABC-1D23');
    expect(find.textContaining('ABC-1D23'), findsWidgets); // título
    await t.pageBack();
    await settle(t);
    expect(find.text('ABC-1D23'), findsOneWidget); // cartão da lista
    expect(find.textContaining('José da Silva'), findsOneWidget);
    expect(store.contactsOf(ContactKind.cliente).length, 1);
    await settle(t);
  });

  testWidgets('novo sinistro vazio é descartado ao voltar', (t) async {
    await start(t);
    await tap(t, find.text('Sinistros').last);
    await tap(t, find.text('Novo'));
    expect(store.claims.length, 1);
    await t.pageBack();
    await settle(t);
    expect(store.claims, isEmpty);
    expect(store.settings.nextNumber, 1);
    await settle(t);
  });

  testWidgets('tipo de atendimento mostra seção da seguradora', (t) async {
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

  testWidgets('status: aprovar pede nome e registra', (t) async {
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

  testWidgets('duplicar e excluir', (t) async {
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

  testWidgets('orçamento: novo item, editar, aprovar, excluir e desfazer', (t) async {
    await start(t);
    final c = seed();
    await openFirstClaim(t);
    await tab(t, 'Orçamento');

    await tap(t, find.text('Novo item'));
    await type(t, find.widgetWithText(TextField, 'Descrição (peça ou serviço)'),
        'Farol esquerdo');
    await type(t, field('Preço unitário da peça'), '450,50');
    await t.pump();
    await tap(t, find.text('Salvar'));
    expect(c.items.length, 1);
    expect(c.items.first.price, closeTo(450.5, 0.001));
    expect(find.text('Farol esquerdo'), findsOneWidget);

    // editar tocando no item
    await tap(t, find.text('Farol esquerdo'));
    await type(t, find.widgetWithText(TextField, 'Descrição (peça ou serviço)'),
        'Farol direito');
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
    await settle(t);
  });

  testWidgets('orçamento: itens do catálogo, outros custos e desconto', (t) async {
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

  testWidgets('avarias: marcar no carro e gerar itens', (t) async {
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
    expect(c.items.length, 2); // reparo + pintura do capô
    await settle(t);
  });

  testWidgets('histórico: anotar acompanhamento', (t) async {
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

  testWidgets('total no rodapé leva à aba Orçamento', (t) async {
    await start(t);
    seed();
    await openFirstClaim(t);
    await tap(t, find.text('Total '));
    expect(find.text('Novo item'), findsOneWidget);
    await settle(t);
  });

  testWidgets('lista: busca, filtro de status e ordenação', (t) async {
    await start(t);
    seed(customer: 'Ana', plate: 'AAA-1A11');
    final b = seed(customer: 'Bruno', plate: 'BBB-2B22');
    store.setStatus(b, ClaimStatus.emReparo);
    await tap(t, find.text('Sinistros').last);
    expect(find.text('AAA-1A11'), findsOneWidget);
    expect(find.text('BBB-2B22'), findsOneWidget);

    await type(t, find.byType(TextField).first, 'bbb2');
    await settle(t);
    expect(find.text('AAA-1A11'), findsNothing);
    expect(find.text('BBB-2B22'), findsOneWidget);
    await type(t, find.byType(TextField).first, '');
    await settle(t);

    await tap(t, find.widgetWithText(FilterChip, ClaimStatus.emReparo.label));
    expect(find.text('AAA-1A11'), findsNothing);
    expect(find.text('BBB-2B22'), findsOneWidget);

    await tap(t, find.byTooltip('Ordenar'));
    await tap(t, find.text('Maior valor'));
    await settle(t);
  });

  testWidgets('desktop: novo item em diálogo e PDF', (t) async {
    await start(t, size: const Size(1366, 768));
    final c = seed();
    await openFirstClaim(t);
    await tab(t, 'Orçamento');
    await tap(t, find.text('Novo item'));
    await type(t, find.widgetWithText(TextField, 'Descrição (peça ou serviço)'),
        'Grade');
    await t.pump();
    await tap(t, find.text('Salvar'));
    expect(c.items.single.description, 'Grade');
    await tap(t, find.byTooltip('PDF do orçamento'));
    expect(find.text('Salvar arquivo PDF'), findsOneWidget);
    await settle(t);
  });
}
