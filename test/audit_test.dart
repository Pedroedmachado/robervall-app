import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/backup_merge.dart';
import 'package:funilar/calc.dart';
import 'package:funilar/docs.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/models.dart';
import 'package:funilar/modules.dart';
import 'package:funilar/receipt_parser.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/stock_entry.dart';
import 'package:funilar/store.dart';
import 'package:funilar/updater.dart';

/// Correções da auditoria (segurança, dados e leitura de notas).
void main() {
  Future<AppStore> openStore() async => AppStore.open(
      assumeLicense: License.full(),
      dir: await Directory.systemTemp.createTemp('funilar_audit'));

  test('nome de arquivo vindo do JSON nunca vira caminho', () {
    expect(safeFileName('foto_1.jpg'), 'foto_1.jpg');
    for (final bad in ['../../x.json', r'..\x', '/etc/passwd', r'C:\Windows\x', 'a/b.jpg', '.oculto', 'x\u0000.jpg']) {
      expect(safeFileName(bad), '', reason: bad);
    }
    final c = Claim.fromJson({
      'sourcePdf': '../../dados.json',
      'photos': [
        {'fileName': '../fora.jpg'},
        {'fileName': 'ok.jpg'}
      ],
    });
    expect(c.sourcePdf, '');
    expect(c.photos.map((p) => p.fileName), ['', 'ok.jpg']);
    expect(FinanceEntry.fromJson({'receipt': r'..\..\x'}).receiptFile, '');
    expect(StockItem.fromJson({'photo': '/tmp/x'}).photo, '');
    expect(StoredDoc.fromJson({'file': '../x.pdf'}).file, '');
  });

  test('atualização: só versão "v1.2.3" e download do GitHub por HTTPS', () {
    expect(validReleaseTag('v1.0.121'), isTrue);
    expect(validReleaseTag('1.2'), isTrue);
    for (final bad in ['v1.0.1; rm -rf ~', r'v1$(calc)', '../v1.0.1', 'v1.0.1 ', '']) {
      expect(validReleaseTag(bad), isFalse, reason: bad);
    }
    expect(trustedDownloadUrl('https://github.com/a/b/releases/download/v1/x.zip'), isTrue);
    expect(trustedDownloadUrl('https://objects.githubusercontent.com/x'), isTrue);
    expect(trustedDownloadUrl('http://github.com/a/b/x.zip'), isFalse);
    expect(trustedDownloadUrl('https://github.com.evil.example/x.zip'), isFalse);
    expect(trustedDownloadUrl('https://evil.example/github.com/x.zip'), isFalse);
  });

  test('backup não promove usuário nem troca senha; usuário novo entra desativado', () {
    final (out, r) = mergeBackupJson({
      'claims': [
        {'id': 'c1', 'number': 'FN-0001'}
      ],
      'users': [
        {'id': 'u1', 'name': 'Zé', 'role': 'producao', 'pin': 'HASH-DAQUI', 'salt': 's1', 'active': true}
      ],
    }, {
      'claims': [],
      'users': [
        {'id': 'u1', 'name': 'Zé', 'role': 'admin', 'pin': 'HASH-DO-BACKUP', 'salt': 's2', 'active': true},
        {'id': 'u2', 'name': 'Invasor', 'role': 'admin', 'pin': 'X', 'salt': 'y', 'active': true},
      ],
    });
    final users = (out['users'] as List).cast<Map>();
    final ze = users.firstWhere((u) => u['id'] == 'u1');
    expect(ze['role'], 'producao');
    expect(ze['pin'], 'HASH-DAQUI');
    final novo = users.firstWhere((u) => u['id'] == 'u2');
    expect(novo['active'], isFalse);
    expect(r.inactiveUsers, 1);
    expect(r.summary(), contains('desativado'));
  });

  test('mescla: mesmo id casa antes de "parecido"; ids compostos acompanham', () {
    Map<String, dynamic> e(String id) =>
        {'id': id, 'isIncome': false, 'date': '2026-11-01T10:00:00.000', 'amount': 50.0, 'description': 'Lixa'};
    final (out, _) = mergeBackupJson({
      'claims': [
        {'id': 'c1', 'number': 'FN-0001'}
      ],
      'entries': [e('a')],
    }, {
      'claims': [],
      'entries': [e('b'), e('a')], // dois gastos iguais; "a" é o mesmo daqui
    });
    final ids = (out['entries'] as List).map((x) => (x as Map)['id']).toList();
    expect(ids..sort(), ['a', 'b']); // nada de dois registros com o mesmo id

    // mesmo sinistro importado nos dois aparelhos (ids diferentes): o lucro
    // do caixa do backup passa a apontar para o orçamento daqui
    final (out2, _) = mergeBackupJson({
      'claims': [
        {'id': 'AQUI', 'number': 'FN-0007', 'claimNumber': '555', 'insurerName': 'Porto'}
      ],
    }, {
      'claims': [
        {'id': 'LA', 'number': 'FN-0003', 'claimNumber': '555', 'insurerName': 'Porto'}
      ],
      'cash': [
        {'id': 'lucro-LA', 'in': true, 'date': '2026-11-02T10:00:00.000', 'amount': 300.0, 'description': 'Lucro líquido FN-0003', 'claim': 'LA'}
      ],
    });
    final cash = (out2['cash'] as List).single as Map;
    expect(cash['id'], 'lucro-AQUI');
    expect(cash['claim'], 'AQUI');
    expect((out2['claims'] as List).length, 1);
  });

  test('mescla: estoque daqui (mais novo) não volta atrás e a baixa das peças acompanha', () async {
    final s = await openStore();
    final farol = StockItem(kind: StockKind.peca, name: 'Farol Gol', partNumber: 'F1', qty: 10, cost: 100);
    s.upsertStock(farol);
    final zip = await s.exportBackup(); // backup com 10 no estoque
    // depois do backup: orçamento aprovado usa 2 faróis do estoque
    final c = s.newClaim()..customerName = 'Ana';
    c.items = [BudgetItem(description: 'Farol Gol', op: ItemOp.troca, qty: 2, price: 300, stockId: farol.id)];
    s.setStatus(c, ClaimStatus.aprovado);
    final after = farol.qty;
    expect(after, lessThan(10));
    await s.importBackup(zip);
    final f = s.stock.single;
    expect(f.qty, after, reason: 'o saldo daqui é mais novo que o backup');
    // reabrir devolve exatamente o que saiu (nem mais, nem menos)
    s.setStatus(s.claims.single, ClaimStatus.aberto);
    expect(s.stock.single.qty, 10);
    await s.flush();
    s.dispose();
  });

  test('duplicar orçamento não leva insumos, PDF nem conclusão do original', () async {
    final s = await openStore();
    final c = s.newClaim()
      ..customerName = 'Ana'
      ..sourcePdf = 'orig.pdf'
      ..concludedAt = DateTime(2026, 1, 5)
      ..supplies = [SupplyUse(stockId: 'x', name: 'Lixa', qty: 2, unit: 'folha', unitCost: 1)]
      ..items = [BudgetItem(description: 'Porta', done: true)];
    final d = s.duplicate(c);
    expect(d.supplies, isEmpty);
    expect(d.sourcePdf, '');
    expect(d.concludedAt, isNull);
    expect(d.items.single.done, isFalse);
    expect(c.sourcePdf, 'orig.pdf');
    await s.flush();
    s.dispose();
  });

  test('linhas iguais de propósito não são juntadas ao reabrir (arquivo novo)', () async {
    final s = await openStore();
    final c = s.newClaim()..customerName = 'Ana';
    c.items = [
      BudgetItem(description: 'Porta dianteira', op: ItemOp.reparo, laborHours: 2),
      BudgetItem(description: 'Porta dianteira', op: ItemOp.reparo, laborHours: 1, laborType: LaborType.mecanica),
    ];
    s.touch(c);
    await s.flush();
    final again = await AppStore.open(assumeLicense: License.full(), dir: s.baseDir);
    expect(again.claims.single.items.length, 2);
    expect(jsonDecode(await File('${s.baseDir.path}/dados.json').readAsString())['version'], 2);
    s.dispose();
    again.dispose();
  });

  test('arquivo de dados ilegível: guarda a cópia, avisa e não grava pela metade', () async {
    final dir = await Directory.systemTemp.createTemp('funilar_bad');
    await File('${dir.path}/dados.json').writeAsString('{"claims": [ {"id": "c1"} ], "cash": "quebrado" ');
    final s = await AppStore.open(assumeLicense: License.full(), dir: dir);
    expect(s.loadError, isNotNull);
    expect(s.claims, isEmpty);
    final copies = dir.listSync().where((f) => f.path.contains('corrompido')).toList();
    expect(copies.length, 1);
    s.dispose();
  });

  test('subtotal inclui a mão de obra por peça', () {
    final c = Claim(items: [BudgetItem(op: ItemOp.reparo, perPiece: true, piecePrice: 500)]);
    final t = computeTotals(c, Settings());
    expect(t.total, 500);
    expect(t.subtotal, 500);
  });

  test('nota: preço antes da quantidade, produto com "TOTAL"/"CHAVE" no nome, peso não é item', () {
    final r = parseReceipt(const [
      'AUTO PECAS CENTRAL',
      'FAROL ESQ GOL 300,00 1 300,00',
      'PARAFUSO M8 1,50 2 3,00',
      'OLEO TOTAL QUARTZ 5W30 2 UN 45,00 90,00',
      'CHAVE DE SETA GOL G5 1 UN 89,00 89,00',
      'TOTAL 482,00',
      'PESO BRUTO PESO LIQUIDO',
      '1 VOLUME 5,000 5,000',
    ]);
    expect(r.items.length, 4, reason: r.items.map((e) => e.description).join(' | '));
    expect(r.items[0].qty, 1);
    expect(r.items[0].unitPrice, 300);
    expect(r.items[1].qty, 2);
    expect(r.items[1].unitPrice, 1.5);
    expect(r.items[2].description.toUpperCase(), startsWith('OLEO TOTAL QUARTZ'));
    expect(r.items[3].description.toUpperCase(), startsWith('CHAVE DE SETA'));
    expect(r.total, 482); // e não os 90,00 do óleo
    expect(r.itemsSum, 482);
  });

  test('nota em latas somando em item cadastrado direto em ml', () {
    final verniz = StockItem(kind: StockKind.material, name: 'Verniz HS 900ML', unit: 'ml', qty: 100, cost: 0.1);
    final d = parseReceipt(const [
      'TINTAS EXEMPLO',
      'VERNIZ HS 900ML',
      '2,00 QUART 89,00 178,00',
      'TOTAL 178,00',
    ]);
    final lines = planStockEntry(d, [verniz]);
    expect(lines.single.match, same(verniz));
    applyStockEntry(lines);
    expect(verniz.qty, 100 + 1800);
    expect(verniz.cost, closeTo(89 / 900, 1e-9));
  });

  test('PIN: depois de 5 erros seguidos precisa esperar', () async {
    final s = await openStore();
    final u = await s.saveUser(AppUser(id: newId(), name: 'Admin', role: Role.admin),
        newPin: '1234');
    for (var i = 0; i < 5; i++) {
      expect(await s.login(u, '0000'), isFalse);
    }
    expect(s.pinWait(u), greaterThan(Duration.zero));
    expect(await s.login(u, '1234'), isFalse, reason: 'bloqueado mesmo com o PIN certo');
    expect(s.pinMessage(u), contains('Muitas tentativas'));
    s.dispose();
  });
}
