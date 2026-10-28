// Gera exemplos para conferência visual (PDF + capturas da pré-visualização).
// Só roda quando SAMPLE_OUT está definido (no CI); nos testes normais é pulado.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/models.dart';
import 'package:funilar/pdf_report.dart';
import 'package:funilar/store.dart';
import 'package:funilar/theme.dart';
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
  });

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
}
