// Gera exemplos para conferência visual (PDF + capturas da pré-visualização).
// Só roda quando SAMPLE_OUT está definido (no CI); nos testes normais é pulado.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/complements.dart';
import 'package:funilar/models.dart';
import 'package:funilar/pdf_report.dart';
import 'package:funilar/receipt_parser.dart';
import 'package:funilar/store.dart';
import 'package:funilar/theme.dart';
import 'package:funilar/ui/budget_tab.dart';
import 'package:funilar/ui/contacts_page.dart';
import 'package:funilar/ui/finance_page.dart';
import 'package:funilar/ui/quote_preview_page.dart';

void main() {
  final out = Platform.environment['SAMPLE_OUT'];
  final skip = out == null ? 'só no CI (SAMPLE_OUT)' : null;
  late AppStore store;
  late Claim claim;

  Future<void> loadFont(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var any = false;
    for (final p in paths) {
      final f = File(p);
      if (f.existsSync()) {
        loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
        any = true;
      }
    }
    if (any) await loader.load();
  }

  setUpAll(() async {
    if (out == null) return;
    const dv = '/usr/share/fonts/truetype/dejavu';
    await loadFont('Roboto', ['$dv/DejaVuSans.ttf', '$dv/DejaVuSans-Bold.ttf']);
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    await loadFont('MaterialIcons',
        ['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);

    store = await AppStore.open(
        dir: await Directory.systemTemp.createTemp('funilar_sample'));
    store.settings
      ..shopName = 'Funilaria Exemplo'
      ..shopDoc = '12.345.678/0001-90'
      ..shopAddress = 'Rua das Oficinas, 100 - São Paulo/SP'
      ..shopPhone = '(11) 99999-0000';
    BudgetItem troca(String d, double price, double mo, double p,
            [PartOrigin o = PartOrigin.nenhuma]) =>
        BudgetItem(
            description: d,
            op: ItemOp.troca,
            price: price,
            laborHours: mo,
            paintHours: p,
            origin: o);
    BudgetItem rep(String d, double mo, double p, {bool ri = false}) =>
        BudgetItem(
            description: d,
            op: mo > 0 ? ItemOp.reparo : ItemOp.pintura,
            laborHours: mo,
            paintHours: p,
            removeInstall: ri);
    claim = store.newClaim()
      ..type = ClaimType.seguradora
      ..status = ClaimStatus.aprovado
      ..customerName = 'Maria Aparecida Oliveira'
      ..customerPhone = '(11) 98888-7777'
      ..insurerName = 'Seguradora Exemplo'
      ..claimNumber = '2026-004512'
      ..regulatorName = 'Carlos Perito'
      ..deductible = 2500
      ..dueDate = DateTime(2026, 11, 20)
      ..vehicle = Vehicle(
          plate: 'ABC-1D23',
          brand: 'Volkswagen',
          model: 'Gol 1.0',
          year: '2019',
          color: 'Prata',
          fipeValue: 42000)
      ..damages = {'capo': 3, 'parachoque_d': 3, 'farol_e': 3, 'lateral_te': 2}
      ..items = [
        troca('Capô', 500, 0.5, 4, PartOrigin.usada),
        troca('Para-choque dianteiro', 250, 1, 4, PartOrigin.usada),
        troca('Farol esquerdo', 300, 1, 0, PartOrigin.original),
        troca('Para-lama dianteiro esquerdo', 300, 1, 4),
        troca('Porta dianteira esquerda', 500, 1, 4),
        rep('Lateral traseira esquerda', 3, 3),
        rep('Porta traseira esquerda', 2, 3),
        rep('Para-choque traseiro', 1, 4, ri: true),
        rep('Retrovisor esquerdo', 0.5, 0, ri: true),
        rep('Teto', 0, 2),
        troca('Roda', 150, 0, 0, PartOrigin.original),
        BudgetItem(
            description: 'Semi eixo',
            op: ItemOp.troca,
            price: 400,
            laborHours: 4,
            laborType: LaborType.mecanica),
        BudgetItem(
            description: 'Alinhamento e balanceamento',
            op: ItemOp.servico,
            price: 120),
      ];
    final joao = Contact(
        kind: ContactKind.funcionario,
        name: 'João pintor',
        payType: PayType.porPeca,
        rate: 35);
    store.upsertContact(joao);
    final baiano = Contact(
        kind: ContactKind.funcionario,
        name: 'Baiano',
        outsourced: true,
        service: OutsourcedService.funilaria,
        payType: PayType.empreita,
        rate: 500);
    final ze = Contact(
        kind: ContactKind.funcionario,
        name: 'Zé martelinho',
        outsourced: true,
        service: OutsourcedService.martelinho,
        payType: PayType.porPeca,
        rate: 80);
    store.upsertContact(baiano);
    store.upsertContact(ze);
    claim.crew = [
      CrewMember(role: OutsourcedService.pintura, contactId: joao.id),
      CrewMember(role: OutsourcedService.funilaria, contactId: baiano.id),
      CrewMember(role: OutsourcedService.martelinho, contactId: ze.id, pieces: 3),
    ];
    claim.approvedAt = DateTime.now();
    // complementos da troca da porta dianteira esquerda
    final porta = claim.items
        .firstWhere((i) => i.description == 'Porta dianteira esquerda');
    addComplements(claim, porta, [
      for (final (comp, on) in complementsFor(porta))
        if (on && comp.removeInstall) comp
    ]);
    final now = DateTime.now();
    DateTime day(int d) => DateTime(now.year, now.month, d);
    store.entries.addAll([
      FinanceEntry(
          description: 'Aluguel do galpão',
          category: ExpenseCategory.fixo,
          amount: 3500,
          recurring: true,
          date: day(5)),
      FinanceEntry(
          category: ExpenseCategory.funcionario,
          payType: PayType.salario,
          contact: 'Marcos',
          description: 'Salário · Marcos',
          amount: 2400,
          recurring: true,
          date: day(5)),
      FinanceEntry(
          category: ExpenseCategory.funcionario,
          payType: PayType.porPeca,
          pieces: 12,
          pieceValue: 35,
          amount: 420,
          contact: 'João pintor',
          description: 'Pintura de peças',
          date: day(10)),
      FinanceEntry(
          category: ExpenseCategory.funcionario,
          outsourced: true,
          service: OutsourcedService.funilaria,
          payType: PayType.empreita,
          amount: 800,
          contact: 'Funilaria do Zé',
          description: 'Funilaria lateral do Gol',
          claimId: claim.id,
          date: day(12)),
      FinanceEntry(
          description: 'Tinta e verniz',
          category: ExpenseCategory.materiais,
          amount: 650,
          date: day(8)),
      FinanceEntry(
          description: 'Peças do Gol',
          category: ExpenseCategory.fornecedor,
          amount: 1600,
          contact: 'Autopeças Central',
          claimId: claim.id,
          date: day(9)),
    ]);
    store.syncCrewCosts(claim);
  });

  final shotKey = GlobalKey();
  Widget app(Widget home) => RepaintBoundary(
        key: shotKey,
        child: StoreScope(
          store: store,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            home: home,
          ),
        ),
      );

  Future<void> shot(WidgetTester tester, String name) async {
    await expectLater(
        find.byKey(shotKey), matchesGoldenFile('goldens/$name.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 7));
  }

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('captura financeiro', (tester) async {
    size(tester, const Size(420, 2000));
    await tester.pumpWidget(app(const FinancePage()));
    await tester.pumpAndSettle();
    await shot(tester, 'financeiro_celular');
  }, skip: skip != null);

  for (final (name, entry) in [
    (
      'lancamento_por_peca',
      () => FinanceEntry(
          category: ExpenseCategory.funcionario,
          payType: PayType.porPeca,
          pieces: 12,
          pieceValue: 35,
          contact: 'João pintor')
        ..syncPieceAmount()
    ),
    (
      'lancamento_terceirizado',
      () => FinanceEntry(
          category: ExpenseCategory.funcionario,
          outsourced: true,
          payType: PayType.empreita,
          amount: 800,
          contact: 'Funilaria do Zé')
    ),
  ]) {
    testWidgets('captura $name', (tester) async {
      size(tester, const Size(420, 1100));
      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => editFinanceEntry(context, entry()),
              child: const Text('abrir'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await shot(tester, name);
    }, skip: skip != null);
  }

  testWidgets('captura nota_lida', (tester) async {
    size(tester, const Size(420, 1700));
    final data = parseReceipt(const [
      'ART COLOR TINTAS',
      'RESERVA 0819365',
      '22/09/2026-17:19   VEND: 00010',
      'VERNIZ A.SOLIDOS HS-2X1 13000 C/CAT.SKY',
      '4,00 QUART   89,00   356,00',
      'ACELERADOR SECAGEM RRA- 1LT SIKKENS',
      '1,00 LITRO   53,90   53,90',
      'TOTAL :   409,90',
      'A vista',
    ]);
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => editFinanceEntry(
                context, data.toEntry()..receiptFile = 'nota_exemplo.jpg',
                banner:
                    'Nota lida: Reserva 0819365 · 2 itens · total R\$ 409,90. Resumo preenchido abaixo — confira antes de salvar.'),
            child: const Text('abrir'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await shot(tester, 'nota_lida');
  }, skip: skip != null);

  test('gera PDFs de exemplo', () async {
    final dir = Directory(out!)..createSync(recursive: true);
    File('${dir.path}/orcamento-exemplo.pdf')
        .writeAsBytesSync(await buildClaimPdf(store, claim, withPhotos: false));
    File('${dir.path}/vistoria-exemplo.pdf').writeAsBytesSync(
        await buildClaimPdf(store, claim, withPhotos: false, withPrices: false));
  }, skip: skip);

  for (final (name, size) in [
    ('preview_desktop', const Size(1000, 2600)),
    ('preview_celular', const Size(400, 3000)),
  ]) {
    testWidgets('captura $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(StoreScope(
        store: store,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          home: QuotePreviewPage(claimId: claim.id),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
          find.byType(QuotePreviewPage), matchesGoldenFile('goldens/$name.png'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    }, skip: skip != null);
  }

  testWidgets('captura orcamento_complementos', (tester) async {
    size(tester, const Size(420, 3700));
    await tester.pumpWidget(app(Scaffold(body: BudgetTab(claim: claim))));
    await tester.pumpAndSettle();
    await shot(tester, 'orcamento_complementos');
  }, skip: skip != null);

  testWidgets('captura janela_complementos', (tester) async {
    size(tester, const Size(420, 1000));
    final c = Claim(items: [
      BudgetItem(description: 'Porta traseira direita', op: ItemOp.troca, price: 900)
    ]);
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => offerComplements(context, c, c.items.first),
            child: const Text('abrir'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await shot(tester, 'janela_complementos');
  }, skip: skip != null);

  testWidgets('captura cadastro_funcionario', (tester) async {
    size(tester, const Size(420, 1200));
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => editContact(
                context,
                Contact(
                    kind: ContactKind.funcionario,
                    name: 'Carlos Pinturas',
                    outsourced: true,
                    service: OutsourcedService.pintura,
                    payType: PayType.porPeca,
                    rate: 40,
                    phone: '(11) 97777-6666')),
            child: const Text('abrir'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await shot(tester, 'cadastro_funcionario');
  }, skip: skip != null);
}
