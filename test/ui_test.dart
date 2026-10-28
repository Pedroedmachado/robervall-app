import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robervall/main.dart';
import 'package:robervall/models.dart';
import 'package:robervall/pdf_report.dart';
import 'package:robervall/store.dart';

/// Abre todas as telas em tamanho de celular e de desktop.
/// Erros de layout (estouro, exceções de build) fazem o teste falhar.
void main() {
  late AppStore store;
  late Claim claim;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('robervall_test');
    store = await AppStore.open(dir: dir);
    claim = store.newClaim()
      ..type = ClaimType.seguradora
      ..status = ClaimStatus.aguardandoAprovacao
      ..customerName = 'Maria Aparecida dos Santos Oliveira'
      ..customerPhone = '(11) 99999-0000'
      ..insurerName = 'Seguradora Exemplo de Nome Comprido'
      ..claimNumber = '2026-000123'
      ..regulatorName = 'Carlos Perito'
      ..deductible = 2500
      ..dueDate = DateTime.now().subtract(const Duration(days: 2))
      ..vehicle = Vehicle(
        plate: 'ABC-1D23',
        brand: 'Volkswagen',
        model: 'Polo Highline 1.0 TSI Flex Aut. (versão comprida)',
        year: '2023',
        fipeValue: 98000,
        fipeCode: '005123-4',
      )
      ..damages = {'capo': 2, 'parachoque_d': 3}
      ..items = [
        BudgetItem(
            description: 'Para-choque dianteiro com nome bem comprido',
            op: ItemOp.troca,
            origin: PartOrigin.original,
            price: 1890.5,
            laborHours: 1.5,
            supplier: 'Autopeças Central'),
        BudgetItem(description: 'Capô', op: ItemOp.reparo, laborHours: 3),
        BudgetItem(description: 'Capô', op: ItemOp.pintura, paintHours: 3),
        BudgetItem(
            description: 'Alinhamento',
            op: ItemOp.servico,
            price: 120,
            approved: false),
      ];
    store.newClaim().customerName = 'Cliente particular';
    store.rememberContactsFrom(claim);
    await store.flush();
  });

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RobervallApp(store: store));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  for (final (name, size) in [
    ('celular', const Size(390, 844)),
    ('celular pequeno', const Size(360, 640)),
    ('desktop', const Size(1366, 768)),
  ]) {
    testWidgets('navega por todas as telas ($name)', (tester) async {
      await pumpApp(tester, size);
      expect(find.textContaining('Em aberto'), findsWidgets);

      for (final page in ['Sinistros', 'Catálogo', 'Cadastros', 'Ajustes', 'Painel']) {
        await tapText(tester, page);
      }

      // abre o sinistro pela lista
      await tapText(tester, 'Sinistros');
      await tester.tap(find.textContaining('Polo Highline').first);
      await tester.pumpAndSettle();
      expect(find.textContaining(claim.number), findsWidgets);

      for (final tab in ['Avarias', 'Fotos', 'Orçamento', 'Histórico', 'Dados']) {
        await tester.tap(find.textContaining(tab).last);
        await tester.pumpAndSettle();
      }

      // gera itens pelo mapa de avarias
      await tester.tap(find.textContaining('Avarias').last);
      await tester.pumpAndSettle();
      final gen = find.text('Gerar itens no orçamento');
      await tester.ensureVisible(gen);
      await tester.pumpAndSettle();
      await tester.tap(gen);
      await tester.pumpAndSettle();

      // editor de item
      await tester.tap(find.textContaining('Orçamento').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novo item'));
      await tester.pumpAndSettle();
      expect(find.text('Tipo de mão de obra'), findsWidgets);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      // seleção do catálogo
      await tester.tap(find.text('Do catálogo'));
      await tester.pumpAndSettle();
      expect(find.text('Buscar no catálogo'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // troca de status
      await tester.tap(find.text(claim.status.label).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ClaimStatus.emReparo.label).last);
      await tester.pumpAndSettle();
      expect(claim.status, ClaimStatus.emReparo);

      // opções do PDF
      await tester.tap(find.byIcon(Icons.picture_as_pdf_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Gerar PDF'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
    });
  }

  test('gera o PDF do orçamento e da vistoria', () async {
    final a = await buildClaimPdf(store, claim);
    final b = await buildClaimPdf(store, claim, withPrices: false);
    expect(a.length, greaterThan(1000));
    expect(String.fromCharCodes(a.take(5)), '%PDF-');
    expect(b.length, greaterThan(1000));
  });

  test('backup ida e volta', () async {
    final zip = await store.exportBackup();
    final dir = await Directory.systemTemp.createTemp('robervall_restore');
    final other = await AppStore.open(dir: dir);
    await other.importBackup(zip);
    expect(other.claims.length, store.claims.length);
    expect(other.claims.first.items.length, store.claims.first.items.length);
  });
}
