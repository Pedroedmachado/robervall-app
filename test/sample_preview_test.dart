// Gera exemplos para conferência visual (PDF + capturas da pré-visualização).
// Só roda quando SAMPLE_OUT está definido (no CI); nos testes normais é pulado.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/modules.dart';
import 'package:funilar/format.dart' show hideMoney;
import 'package:funilar/complements.dart';
import 'package:funilar/models.dart';
import 'package:funilar/pdf_report.dart';
import 'package:funilar/receipt_parser.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/ui/stock_page.dart';
import 'package:funilar/ui/settings_page.dart';
import 'package:funilar/ui/license_ui.dart';
import 'package:funilar/ui/users_ui.dart';
import 'package:funilar/ui/os_tab.dart';
import 'package:funilar/ui/damage_tab.dart';
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

    store = await AppStore.open(assumeLicense: License.full(), 
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
        BudgetItem(
            description: 'Para-lama traseiro direito',
            op: ItemOp.reparo,
            perPiece: true,
            piecePrice: 380,
            doPaint: true),
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
    for (final st in [
      StockItem(
          name: 'Farol esquerdo',
          fits: 'Gol G6 2013-2016',
          qty: 1,
          cost: 280,
          price: 390,
          corridor: '1',
          shelf: 'B5',
          slot: '3'),
      StockItem(
          name: 'Retrovisor esquerdo elétrico',
          fits: 'Gol G5',
          qty: 2,
          cost: 150,
          price: 220,
          corridor: '2',
          shelf: 'A1'),
      StockItem(
          kind: StockKind.material,
          name: 'Lixa P320',
          qty: 80,
          unit: 'folha',
          cost: 2.5,
          corridor: '3',
          shelf: 'C1'),
      StockItem(
          kind: StockKind.cliente,
          name: 'Para-choque dianteiro retirado',
          claimId: claim.id,
          corridor: '4',
          shelf: 'D2',
          slot: '1'),
      StockItem(
          kind: StockKind.material,
          name: 'Verniz HS 2x1',
          qty: 3,
          unit: 'quarto',
          cost: 89),
      StockItem(kind: StockKind.material, name: 'Massa poliéster', qty: 0, unit: 'lata', cost: 45),
      StockItem(
          kind: StockKind.material,
          name: 'Thinner TH700 900ml',
          unit: 'ml',
          packName: 'lata',
          packSize: 900,
          packCost: 41,
          cost: 41 / 900,
          qty: 1800,
          corridor: '3',
          shelf: 'C2'),
    ]) {
      store.upsertStock(st);
    }
    StockItem byName(String n) => store.stock.firstWhere((e) => e.name == n);
    final capo = claim.items.firstWhere((i) => i.description == 'Capô');
    store.issueSupply(claim, byName('Lixa P320'), 12, itemId: capo.id);
    store.issueSupply(claim, byName('Verniz HS 2x1'), 1, itemId: capo.id);
    claim.items.first.done = true;
    claim.items[1].done = true;
    claim.preDamages.addAll({'porta_te': 1, 'teto': 1});
    claim.reception
      ..at = DateTime(2026, 10, 27, 8, 40)
      ..fuel = 1
      ..items.addAll({'Estepe', 'Macaco', 'Chave de roda', 'Documento (CRLV)'})
      ..notes = 'Risco antigo no teto, cliente ciente.';
    claim.vehicle.km = '84.300';
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

  testWidgets('captura estoque', (tester) async {
    size(tester, const Size(420, 900));
    await tester.pumpWidget(app(const StockPage()));
    await tester.pumpAndSettle();
    await shot(tester, 'estoque_celular');
  }, skip: skip != null);

  testWidgets('captura item R&I + R + P', (tester) async {
    size(tester, const Size(420, 1100));
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => editBudgetItem(
                context,
                BudgetItem(
                    description: 'Para-lama dianteiro esquerdo',
                    op: ItemOp.reparo,
                    perPiece: true,
                    piecePrice: 450,
                    removeInstall: true,
                    alsoRepair: true,
                    doPaint: true),
                vehicle: claim.vehicle),
            child: const Text('abrir'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await shot(tester, 'item_ri_r_p');
  }, skip: skip != null);

  for (final (name, prod) in [('os_gestor', false), ('os_producao', true)]) {
    testWidgets('captura $name', (tester) async {
      size(tester, const Size(420, 2300));
      if (prod) {
        gate.user = AppUser(id: 'p', name: 'Zé', role: Role.producao);
        hideMoney = true;
      }
      addTearDown(() {
        gate.user = null;
        hideMoney = false;
      });
      await tester.pumpWidget(app(Scaffold(body: OsTab(claim: claim))));
      await tester.pumpAndSettle();
      await shot(tester, name);
    }, skip: skip != null);
  }

  testWidgets('captura avarias_entrada', (tester) async {
    size(tester, const Size(420, 2600));
    await tester.pumpWidget(app(Scaffold(body: DamageTab(claim: claim))));
    await tester.pumpAndSettle();
    await shot(tester, 'avarias_entrada');
  }, skip: skip != null);

  for (final (name, page) in [
    ('ajustes_licenca', const SettingsPage()),
    ('master_desafio', const MasterPage()),
    ('usuarios', const UsersPage()),
  ]) {
    testWidgets('captura $name', (tester) async {
      size(tester, const Size(420, 1400));
      await tester.pumpWidget(app(page));
      await tester.pumpAndSettle();
      await shot(tester, name);
    }, skip: skip != null);
  }

  testWidgets('captura estoque_insumo', (tester) async {
    size(tester, const Size(420, 1500));
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => editStockItem(context,
                StockItem.fromJson(store.stock.firstWhere((e) => e.name.startsWith('Thinner')).toJson())),
            child: const Text('abrir'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await shot(tester, 'estoque_insumo');
  }, skip: skip != null);

  testWidgets('captura liberar_lixa', (tester) async {
    size(tester, const Size(420, 4200));
    await tester.pumpWidget(app(Scaffold(body: OsTab(claim: claim))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liberar insumo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '2/4 no taco'));
    await tester.pumpAndSettle();
    await shot(tester, 'liberar_lixa');
  }, skip: skip != null);

  testWidgets('captura estoque_peca', (tester) async {
    size(tester, const Size(420, 2300));
    final nova = StockItem(
        name: 'Farol esquerdo',
        partNumber: '5u0-941-005',
        mfrBrand: 'Arteb',
        mfrCode: 'AR-1234',
        condition: 'paralela',
        qty: 1,
        cost: 280,
        price: 390,
        applications: [
          VehicleFit(make: 'Volkswagen', model: 'Gol', yearFrom: 2013, yearTo: 2016, engine: '1.0', version: 'Trend'),
          VehicleFit(make: 'Volkswagen', model: 'Voyage', yearFrom: 2013, yearTo: 2016),
        ]);
    store.stock.firstWhere((e) => e.name == 'Farol esquerdo').partNumber = '5U0941005';
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => editStockItem(context, nova),
            child: const Text('abrir'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await shot(tester, 'estoque_peca');
  }, skip: skip != null);

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
