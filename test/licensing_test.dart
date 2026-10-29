import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/finance.dart';
import 'package:funilar/fipe.dart';
import 'package:funilar/format.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/models.dart';
import 'package:funilar/modules.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/store.dart';

import 'test_keys.dart';

/// Licença real emitida com a chave OFICIAL (todos os módulos).
const realLicense = 'FUNILAR-LICENCA-1\neyJ2IjogMSwgImlkIjogIkxJQy0wMDAxIiwgImNsaWVudGUiOiAiUGVkcm8gLSBvZmljaW5hIHByw7NwcmlhIiwgImRvY3VtZW50byI6ICIiLCAibW9kdWxvcyI6IFsibnVjbGVvIiwgInZpc3RvcmlhIiwgImZpbmFuY2Vpcm8iLCAib2NyIiwgImVxdWlwZSIsICJlc3RvcXVlIiwgInByb2R1Y2FvIiwgImludGVncmFjb2VzIl0sICJlbWl0aWRhIjogIjIwMjYtMTAtMjkiLCAidmFsaWRhZGUiOiBudWxsLCAiYXBhcmVsaG8iOiAiIn0.78ZEtjxMR4mNeaVf5KeNU4L5vsWsBwuYJ2WwLVWFACeKEO8TQGP7Cg08Y8luEWPhwmCjXHW-MkTNDga40N6YBw';

Future<Directory> tmp(String n) => Directory.systemTemp.createTemp(n);

Future<String> testLicense({
  Set<Mod>? modules,
  DateTime? expires,
  String device = '',
}) =>
    signLicense(
        License(
            id: 'T-1',
            customer: 'Oficina Teste',
            modules: modules ?? Mod.values.toSet(),
            issued: DateTime(2026, 10, 1),
            expires: expires,
            device: device),
        testSeed);

Future<AppStore> openTest(Directory d) =>
    AppStore.open(
        dir: d, publicKey: testPub, device: testDevice, enforceLicense: true);

Future<MasterSession> master(AppStore s) async {
  final ch = newMasterChallenge(s.deviceId);
  return s.openMaster(ch, await signMasterChallenge(ch, testSeed));
}

void main() {
  test('sem exigência de licença: abre completo e grava normalmente', () async {
    final d = await tmp('fn_livre');
    final s = await AppStore.open(dir: d, device: testDevice);
    expect(gate.readOnly, isFalse);
    for (final m in Mod.values) {
      expect(gate.active(m), isTrue, reason: m.name);
    }
    s.newClaim();
    await s.flush();
    expect(File('${d.path}/dados.json').readAsStringSync(), contains('FN-0001'));
  });

  group('licença', () {
    test('licença oficial confere com a chave pública do app', () async {
      final r = await verifyLicense(realLicense, deviceId: 'FN-QUALQUER');
      expect(r.status, LicenseStatus.valid);
      expect(r.license!.modules, Mod.values.toSet());
      expect(r.license!.customer, 'Pedro - oficina própria');
    });

    test('rejeita licença adulterada, de outra chave, ilegível ou ausente', () async {
      // troca um módulo no conteúdo e mantém a assinatura
      final body = realLicense.split('\n')[1];
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(body.split('.')[0])));
      final forged = payload.replaceAll('"T-1"', '"T-2"').replaceAll('LIC-0001', 'LIC-9999');
      final fake = 'FUNILAR-LICENCA-1\n'
          '${base64Url.encode(utf8.encode(forged)).replaceAll('=', '')}.${body.split('.')[1]}';
      expect((await verifyLicense(fake, deviceId: 'x')).status, LicenseStatus.invalid);
      // assinada por outra chave (a de teste) não vale no app oficial
      expect((await verifyLicense(await testLicense(), deviceId: 'x')).status,
          LicenseStatus.invalid);
      // um caractere trocado na assinatura
      final sigTampered = realLicense.replaceRange(
          realLicense.length - 5, realLicense.length - 4,
          realLicense[realLicense.length - 5] == 'A' ? 'B' : 'A');
      expect((await verifyLicense(sigTampered, deviceId: 'x')).status, LicenseStatus.invalid);
      expect((await verifyLicense('qualquer coisa', deviceId: 'x')).status, LicenseStatus.invalid);
      expect((await verifyLicense('', deviceId: 'x')).status, LicenseStatus.missing);
      // colada com quebras e espaços no meio continua valendo
      final spaced = realLicense.replaceAllMapped(RegExp(r'.{20}'), (m) => '${m[0]}\n  ');
      expect((await verifyLicense(spaced, deviceId: 'x')).ok, isTrue);
    });

    test('vencida, de outro aparelho e relógio atrasado', () async {
      final exp = await testLicense(expires: DateTime(2026, 6, 30));
      expect((await verifyLicense(exp, deviceId: 'a', publicKey: testPub, now: DateTime(2026, 6, 30, 23))).ok, isTrue);
      expect((await verifyLicense(exp, deviceId: 'a', publicKey: testPub, now: DateTime(2026, 7, 2))).status,
          LicenseStatus.expired);
      final dev = await testLicense(device: 'FN-AAAA-BBBB-CCCC');
      expect((await verifyLicense(dev, deviceId: 'FN-AAAA-BBBB-CCCC', publicKey: testPub)).ok, isTrue);
      expect((await verifyLicense(dev, deviceId: 'FN-OUTRO', publicKey: testPub)).status,
          LicenseStatus.wrongDevice);
      expect((await verifyLicense(await testLicense(), deviceId: 'a', publicKey: testPub,
              now: DateTime(2026, 10, 1), lastSeen: DateTime(2026, 12, 1))).status,
          LicenseStatus.clockRollback);
    });
  });

  group('instalação e módulos', () {
    test('sem licença: só consulta e nada é gravado', () async {
      final d = await tmp('fn_semlic');
      final s = await openTest(d);
      expect(s.license.status, LicenseStatus.missing);
      expect(gate.readOnly, isTrue);
      expect(() => s.newClaim(), throwsA(isA<AccessDenied>()));
      expect(gate.active(Mod.financeiro), isFalse);
      expect(gate.active(Mod.nucleo), isTrue);
      // licença adulterada também é recusada e não é instalada
      final r = await s.installLicense('FUNILAR-LICENCA-1\nabc.def');
      expect(r.ok, isFalse);
      expect(File('${d.path}/licenca.lic').existsSync(), isFalse);
      // instalando a válida, libera
      expect((await s.installLicense(await testLicense())).ok, isTrue);
      expect(gate.readOnly, isFalse);
      s.newClaim();
      await s.flush();
      expect(File('${d.path}/dados.json').readAsStringSync(), contains('FN-0001'));
    });

    test('desligar e religar: bloqueio, persistência e dados intactos', () async {
      final d = await tmp('fn_mod');
      var s = await openTest(d);
      await s.installLicense(await testLicense());
      final farol = StockItem(name: 'Farol esquerdo', qty: 2, cost: 200);
      s.upsertStock(farol);
      final pintor = Contact(kind: ContactKind.funcionario, name: 'Luan', payType: PayType.empreita, rate: 300);
      s.upsertContact(pintor);
      final c = s.newClaim()
        ..items = [BudgetItem(description: 'Farol esquerdo', op: ItemOp.troca, price: 390, paintHours: 1)]
        ..crew = [CrewMember(role: OutsourcedService.pintura, contactId: pintor.id)];
      c.items.first.stockId = farol.id;
      s.upsertEntry(FinanceEntry(amount: 80, claimId: c.id, description: 'Guincho'));
      await s.flush();

      final m = await master(s);
      expect(m.valid, isTrue);
      // Estoque não desliga enquanto a Produção (que depende dele) estiver ligada
      expect(s.impactOf(Mod.estoque, false).blocks, isNotEmpty);
      await expectLater(s.setModuleEnabled(Mod.estoque, false, m), throwsA(isA<AccessDenied>()));
      await s.setModuleEnabled(Mod.producao, false, m);
      await s.setModuleEnabled(Mod.estoque, false, m);
      // Financeiro não desliga com a Leitura de nota (que depende dele) ligada
      expect(s.impactOf(Mod.financeiro, false).blocks, isNotEmpty);
      await s.setModuleEnabled(Mod.ocr, false, m);
      await s.setModuleEnabled(Mod.financeiro, false, m);
      expect(gate.active(Mod.estoque), isFalse);
      // e a Leitura de nota não religa sem o Financeiro
      expect(s.impactOf(Mod.ocr, true).blocks, isNotEmpty);

      // serviços barrados (não só a tela)
      expect(() => s.upsertStock(StockItem(name: 'x')), throwsA(isA<AccessDenied>()));
      expect(() => s.upsertEntry(FinanceEntry(amount: 1)), throwsA(isA<AccessDenied>()));
      expect(() => s.issueSupply(c, farol, 1), throwsA(isA<AccessDenied>()));
      // rotinas automáticas congeladas: aprovar não dá baixa nem lança custo
      s.setStatus(c, ClaimStatus.aprovado);
      expect(farol.qty, 2);
      expect(s.entries.where((e) => isCrewEntry(e)), isEmpty);
      // relatório que usa dados históricos do Financeiro continua certo
      final j = jobCost(c, s.settings, entries: s.entries, contactById: s.contactById, stockById: s.stockById);
      expect(j.otherExpenses, 80);
      expect(j.crew, 300);
      // nenhum dado foi apagado
      await s.flush();
      final saved = jsonDecode(File('${d.path}/dados.json').readAsStringSync()) as Map;
      expect((saved['stock'] as List).length, 1);
      expect((saved['entries'] as List).length, 1);

      // reinicia o app: continua desligado
      s.dispose();
      s = await openTest(d);
      expect(gate.active(Mod.estoque), isFalse);
      expect(gate.active(Mod.financeiro), isFalse);
      expect(s.stock.single.qty, 2);

      // religa: tudo volta e o que ficou congelado é acertado
      final m2 = await master(s);
      await s.setModuleEnabled(Mod.financeiro, true, m2);
      await s.setModuleEnabled(Mod.estoque, true, m2);
      await s.setModuleEnabled(Mod.producao, true, m2);
      expect(s.stock.single.qty, 1); // baixa feita na reativação
      expect(s.entries.where((e) => isCrewEntry(e)).single.amount, 300);
      expect(s.entries.length, 2);
      expect(s.activation.log.map((e) => e['acao']), containsAll(['ligou', 'desligou', 'master']));
    });

    test('só o Master liga/desliga: resposta errada é recusada', () async {
      final d = await tmp('fn_master');
      final s = await openTest(d);
      await s.installLicense(await testLicense());
      final ch = newMasterChallenge(s.deviceId);
      final otherCh = newMasterChallenge(s.deviceId);
      // resposta de outro desafio, inventada ou vazia: nada feito
      for (final resp in [await signMasterChallenge(otherCh, testSeed), 'abc', '']) {
        final sess = await s.openMaster(ch, resp);
        expect(sess.valid, isFalse);
        await expectLater(s.setModuleEnabled(Mod.vistoria, false, sess), throwsA(isA<AccessDenied>()));
      }
      expect(gate.active(Mod.vistoria), isTrue);
      // administrador da empresa também não consegue (não existe atalho)
      await s.saveUser(AppUser(id: 'a', name: 'Dono', role: Role.admin), newPin: '1234');
      expect(gate.can(Perm.usuarios), isTrue);
      final bad = await s.openMaster(ch, '1234');
      await expectLater(s.setModuleEnabled(Mod.vistoria, false, bad), throwsA(isA<AccessDenied>()));
    });

    test('módulo fora da licença nunca liga, nem mexendo no arquivo', () async {
      final d = await tmp('fn_fora');
      final s = await openTest(d);
      await s.installLicense(await testLicense(modules: {Mod.vistoria}));
      expect(gate.active(Mod.financeiro), isFalse);
      final m = await master(s);
      await expectLater(s.setModuleEnabled(Mod.financeiro, true, m), throwsA(isA<AccessDenied>()));
      // edita modulos.json na mão ligando tudo
      final f = File('${d.path}/modulos.json');
      final j = jsonDecode(f.readAsStringSync()) as Map;
      j['ativos'] = Mod.values.map((e) => e.name).toList();
      f.writeAsStringSync(jsonEncode(j));
      s.dispose();
      final s2 = await openTest(d);
      expect(s2.activation.tampered || s2.activation.log.any((e) => e['acao'] == 'aviso'), isTrue);
      expect(gate.active(Mod.financeiro), isFalse); // a licença manda
      expect(gate.active(Mod.vistoria), isTrue);
    });

    test('Integrações desligadas: o app não acessa a internet', () async {
      final d = await tmp('fn_net');
      final s = await openTest(d);
      await s.installLicense(await testLicense(modules: {Mod.vistoria}));
      await expectLater(FipeClient().brands(FipeKind.values.first), throwsA(isA<AccessDenied>()));
    });

    test('campos desconhecidos do arquivo são preservados ao gravar', () async {
      final d = await tmp('fn_extra');
      File('${d.path}/dados.json').writeAsStringSync(jsonEncode({
        'app': 'funilar',
        'claims': [],
        'moduloFuturo': {'registros': [1, 2, 3]},
      }));
      final s = await openTest(d);
      await s.installLicense(await testLicense());
      s.newClaim();
      await s.flush();
      final j = jsonDecode(File('${d.path}/dados.json').readAsStringSync()) as Map;
      expect(j['moduloFuturo'], {'registros': [1, 2, 3]});
    });
  });

  group('usuários e permissões', () {
    test('papéis, PIN com hash, login e autorização pontual', () async {
      final d = await tmp('fn_rbac');
      final s = await openTest(d);
      await s.installLicense(await testLicense());
      expect(gate.can(Perm.financeiroVer), isTrue); // sem usuários: acesso total
      // o primeiro precisa ser administrador com PIN
      await expectLater(
          s.saveUser(AppUser(id: 'p', name: 'Zé', role: Role.producao)),
          throwsA(isA<AccessDenied>()));
      s.users.clear();
      final dono = await s.saveUser(AppUser(id: 'a', name: 'Dono', role: Role.admin), newPin: '4321');
      expect(dono.pinHash, isNot(contains('4321')));
      expect(dono.salt, isNotEmpty);
      final ze = await s.saveUser(AppUser(id: 'p', name: 'Zé', role: Role.producao), newPin: '');
      s.logout();
      expect(s.needsLogin, isTrue);
      expect(gate.can(Perm.osExecutar), isFalse);
      expect(await s.login(dono, '0000'), isFalse);
      expect(await s.login(ze, ''), isTrue);
      expect(gate.can(Perm.valoresVer), isFalse);
      expect(money(10), 'R\$ •••');
      expect(gate.can(Perm.osExecutar), isTrue);
      expect(() => gate.requirePerm(Perm.insumoLiberar), throwsA(isA<AccessDenied>()));
      expect(await s.authorizeOnce(dono, '4321', Perm.insumoLiberar), isTrue);
      expect(await s.authorizeOnce(ze, '', Perm.insumoLiberar), isFalse);
      // último administrador não pode ser desativado
      s.logout();
      await s.login(dono, '4321');
      expect(money(10), 'R\$ 10,00');
      expect(() => s.setUserActive(dono, false), throwsA(isA<AccessDenied>()));
      s.setUserActive(ze, false);
      expect(s.users.length, 2); // desativado, não apagado
      await s.flush();
      final saved = File('${d.path}/dados.json').readAsStringSync();
      expect(saved, isNot(contains('"4321"')));
    });

    test('versão antiga: PIN do gestor vira Administrador e o modo produção vira usuário', () async {
      final d = await tmp('fn_migra');
      File('${d.path}/dados.json').writeAsStringSync(jsonEncode({
        'app': 'funilar',
        'settings': {'managerPin': '1234', 'productionMode': true},
      }));
      final s = await openTest(d);
      await s.installLicense(await testLicense());
      expect(s.users.map((u) => u.role), [Role.admin, Role.producao]);
      expect(s.settings.managerPin, '');
      expect(await s.login(s.users.first, '1234'), isTrue);
    });
  });
}
