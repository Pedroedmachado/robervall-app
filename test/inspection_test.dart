import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/calc.dart';
import 'package:funilar/car3d.dart';
import 'package:funilar/inspection.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/main.dart';
import 'package:funilar/models.dart';
import 'package:funilar/store.dart';

/// Inspeção 3D: catálogo de serviços por gravidade, avarias que viram itens
/// do orçamento, prazo em dias úteis, carro 3D clicável e a tela completa.
void main() {
  group('regras', () {
    test('serviços sugeridos pela peça, tipo e gravidade', () {
      final cat = defaultInspectionServices();
      final porta = partById(CarBody.sedan, 'porta_de')!;
      final leve = suggestedServices(cat, porta, 'amassado', 1);
      final names = leve.map((e) => e.$1.name).toList();
      expect(names, containsAll(['Recuperação e pintura', 'Martelinho de ouro', 'Pintura da peça']));
      expect(names, isNot(contains('Substituição da peça (mão de obra)'))); // só na grave
      expect(names, isNot(contains('Reparo de trinca no vidro')));
      final rp = leve.firstWhere((e) => e.$1.name == 'Recuperação e pintura').$2;
      expect(rp.price, 700);
      expect(rp.minutes, 300);
      // moderada = ×1,3 no preço e no tempo
      final mod = suggestedServices(cat, porta, 'amassado', 2)
          .firstWhere((e) => e.$1.name == 'Recuperação e pintura')
          .$2;
      expect(mod.price, 910);
      expect(mod.minutes, 390);
      // grave libera a troca
      expect(
          suggestedServices(cat, porta, 'amassado', 3).map((e) => e.$1.name),
          contains('Substituição da peça (mão de obra)'));
      // martelinho só para amassado
      expect(suggestedServices(cat, porta, 'risco', 1).map((e) => e.$1.name),
          isNot(contains('Martelinho de ouro')));
      // vidro tem os serviços de vidro
      final vidro = partById(CarBody.sedan, 'parabrisa')!;
      expect(suggestedServices(cat, vidro, 'trinca', 1).map((e) => e.$1.name),
          contains('Reparo de trinca no vidro'));
    });

    test('prazo em dias úteis e tempo', () {
      expect(workDays(0), 0);
      expect(workDays(300), 1);
      expect(workDays(672), 2); // 11h 12min
      expect(hoursText(672), '11h 12min');
      expect(hoursText(45), '45min');
      expect(hoursText(120), '2h');
    });

    test('carroceria pelo modelo e escolhida pelo usuário', () {
      expect(CarBody.guess('Hilux CD SRX'), CarBody.picape);
      expect(CarBody.guess('Ford F-150 Raptor R'), CarBody.picape);
      expect(CarBody.guess('Jeep Compass Longitude'), CarBody.suv);
      expect(CarBody.guess('Golf GTI'), CarBody.hatch);
      expect(CarBody.guess('Corolla XEi'), CarBody.sedan);
      final v = Vehicle(model: 'Corolla')..body = 'picape';
      expect(CarBody.of(v), CarBody.picape);
      expect(Vehicle.fromJson(v.toJson()).body, 'picape');
      expect(partsFor(CarBody.picape).map((p) => p.id), contains('cacamba'));
      expect(partsFor(CarBody.sedan).map((p) => p.id), isNot(contains('cacamba')));
    });

    test('avaria vira itens do orçamento e some junto', () async {
      final store = await AppStore.open(
          assumeLicense: License.full(), dir: await Directory.systemTemp.createTemp('fn_insp'));
      final c = store.newClaim()..vehicle.model = 'Corolla';
      c.items.add(BudgetItem(description: 'Alinhamento', op: ItemOp.servico, price: 120));
      final d = InspectionDamage(partId: 'porta_de', type: 'pintura', severity: 2, services: [
        InspectionService(name: 'Recuperação e pintura', price: 910, minutes: 390),
        InspectionService(name: 'Martelinho de ouro', price: 335, minutes: 120),
        InspectionService(name: 'Insumos de pintura', price: 105, isPart: true),
      ]);
      store.saveInspection(c, d);
      final mine = c.items.where((e) => e.inspectionId == d.id).toList();
      expect(mine.length, 3);
      expect(mine.first.description, 'Porta dianteira esquerda — Recuperação e pintura');
      expect(mine.first.op, ItemOp.servico);
      expect(mine.last.op, ItemOp.troca); // peça/insumo
      expect(computeTotals(c, store.settings).total, 120 + 910 + 335 + 105);
      final sum = summarize(c);
      expect(sum.labor, 1245);
      expect(sum.parts, 105);
      expect(sum.days, 2);
      expect(c.timeline.last.text, contains('Inspeção 3D: Porta dianteira esquerda'));

      // editar troca os itens no mesmo lugar, sem duplicar
      d.services.removeAt(1);
      store.saveInspection(c, d);
      expect(c.items.where((e) => e.inspectionId == d.id).length, 2);
      expect(c.inspection.length, 1);

      // ida e volta
      final back = Claim.fromJson(c.toJson());
      expect(back.inspection.single.services.length, 2);
      expect(back.inspection.single.severity, 2);
      expect(back.items.where((e) => e.inspectionId == d.id).length, 2);

      store.removeInspection(c, d);
      expect(c.inspection, isEmpty);
      expect(c.items.single.description, 'Alinhamento');
      expect(store.inspServices, isNotEmpty);
      store.dispose();
    });

    test('catálogo da inspeção é salvo e volta', () async {
      final dir = await Directory.systemTemp.createTemp('fn_insp2');
      final a = await AppStore.open(assumeLicense: License.full(), dir: dir);
      a.upsertInspService(ServiceTemplate(name: 'Cristalização', category: 'Estética', price: 300, minutes: 90));
      await a.flush();
      a.dispose();
      final b = await AppStore.open(assumeLicense: License.full(), dir: dir);
      final t = b.inspServices.firstWhere((e) => e.name == 'Cristalização');
      expect(t.price, 300);
      expect(t.forSeverity(3).price, 510);
      b.dispose();
    });
  });

  group('carro 3D', () {
    for (final body in CarBody.values) {
      test('${body.label}: todas as peças existem e são clicáveis', () {
        final mesh = buildCar(body);
        final meshParts = mesh.tris.map((t) => t.part).where((p) => p.isNotEmpty).toSet();
        for (final p in partsFor(body)) {
          expect(meshParts, contains(p.id), reason: p.id);
        }
        const size = Size(900, 560);
        // cada peça aparece e é achada pelo clique em alguma das vistas
        const views = [
          Camera3D.frontLeft, Camera3D.rearRight, Camera3D.front, Camera3D.back,
          Camera3D.left, Camera3D.right, Camera3D.top,
        ];
        for (final p in partsFor(body)) {
          var found = false;
          for (final cam in views) {
            final proj = projectMesh(mesh, cam, size);
            for (final t in proj.reversed) {
              if (t.tri.part != p.id) continue;
              final c = Offset((t.a.dx + t.b.dx + t.c.dx) / 3, (t.a.dy + t.b.dy + t.c.dy) / 3);
              if (hitPart(proj, c) == p.id) {
                found = true;
                break;
              }
            }
            if (found) break;
          }
          expect(found, isTrue, reason: '${body.name}: ${p.id} não dá para clicar');
        }
      });
    }

    test('vista lateral esquerda mostra a porta esquerda, não a direita', () {
      final mesh = buildCar(CarBody.sedan);
      const size = Size(900, 560);
      final proj = projectMesh(mesh, Camera3D.left, size);
      final center = projectPoint(mesh.anchors['porta_de']!, Camera3D.left, size);
      expect(hitPart(proj, center + const Offset(0, 25)), 'porta_de');
    });

    testWidgets('gera a imagem do carro para o PDF', (t) async {
      final png = (await t.runAsync(() => renderCarPng(buildCar(CarBody.hatch), Camera3D.frontLeft,
          partColors: {'capo': severityColors[2]!}, pins: {'capo': 1})))!;
      expect(png.length, greaterThan(1000));
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
    });
  });

  testWidgets('tela: clicar na peça, registrar avaria e ver no orçamento', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = (await t.runAsync(() async => AppStore.open(
        assumeLicense: License.full(), dir: await Directory.systemTemp.createTemp('fn_insp3'))))!;
    final c = store.newClaim()
      ..customerName = 'André Figueiredo'
      ..vehicle.plate = 'TXK-4J58'
      ..vehicle.brand = 'Volkswagen'
      ..vehicle.model = 'Golf GTI';
    store.changed();
    await t.pumpWidget(FunilarApp(store: store));
    await t.pumpAndSettle();

    Future<void> tap(Finder f) async {
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    await tap(find.text('Sinistros').last);
    await tap(find.textContaining('Golf GTI').first);
    await tap(find.descendant(of: find.byType(TabBar), matching: find.text('Inspeção 3D')));
    expect(find.text('Resumo da inspeção'), findsOneWidget);
    expect(find.textContaining('Modelo 3D · Hatch'), findsOneWidget);

    // clique no capô do carro 3D
    final st = t.state<Car3DViewState>(find.byType(Car3DView));
    final local = st.screenPointOf('capo')!;
    final box = t.renderObject<RenderBox>(find.byType(Car3DView));
    await t.tapAt(box.localToGlobal(local));
    await t.pumpAndSettle();
    expect(find.text('Peça selecionada'), findsOneWidget);
    expect(find.text('Capô'), findsWidgets);
    expect(find.text('Nenhuma avaria registrada nesta peça.'), findsOneWidget);

    await tap(find.text('Registrar avaria'));
    await tap(find.byKey(const ValueKey('tipo-pintura')));
    await tap(find.byKey(const ValueKey('gravidade-2')));
    expect(find.text('Afeta o acabamento e pede reparo com pintura'), findsOneWidget);
    await tap(find.byKey(const ValueKey('servico-Recuperação e pintura')));
    await tap(find.byKey(const ValueKey('servico-Polimento técnico')));
    final v = t.widget<Text>(find.byKey(const ValueKey('valor-estimado'))).data;
    expect(v, isNot(contains('0,00')));
    await tap(find.text('Salvar avaria'));

    expect(c.inspection.length, 1);
    expect(c.inspection.single.partId, 'capo');
    expect(c.inspection.single.type, 'pintura');
    expect(c.inspection.single.severity, 2);
    expect(c.items.where((e) => e.inspectionId.isNotEmpty).length, 2);
    expect(find.text('Resumo da inspeção'), findsOneWidget);
    expect(find.text('Avarias registradas (1)'), findsOneWidget);
    expect(find.textContaining('Pintura danificada · moderada'), findsOneWidget);
    expect(find.text('Prazo estimado'), findsOneWidget);

    // peça escolhida pela lista e serviço sem avaria
    await tap(find.byKey(const ValueKey('escolher-peca')));
    await tap(find.text('Para-choque traseiro').last);
    await tap(find.text('Adicionar serviço sem avaria'));
    await tap(find.byKey(const ValueKey('servico-Lavagem técnica')));
    await tap(find.text('Salvar serviço'));
    expect(c.inspection.length, 2);
    expect(c.inspection.last.type, '');

    // trocar a carroceria
    await tap(find.byKey(const ValueKey('carroceria')));
    await tap(find.text('Picape').last);
    expect(c.vehicle.body, 'picape');
    expect(find.textContaining('Modelo 3D · Picape'), findsOneWidget);

    // aparece no orçamento
    await tap(find.descendant(of: find.byType(TabBar), matching: find.textContaining('Orçamento')));
    expect(find.text('Capô — Recuperação e pintura'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 7));
  });
}
