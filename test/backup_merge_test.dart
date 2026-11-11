import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/backup_merge.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/models.dart';
import 'package:funilar/receipt_parser.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/stock_entry.dart';
import 'package:funilar/store.dart';

void main() {
  Future<AppStore> openStore() async => AppStore.open(
      assumeLicense: License.full(),
      dir: await Directory.systemTemp.createTemp('funilar_merge'));

  test('importar backup mescla: atualiza o que existe, acrescenta o novo, não apaga nada', () async {
    // --- aparelho A (o backup)
    final a = await openStore();
    final ca = a.newClaim()
      ..customerName = 'Carlos'
      ..vehicle.plate = 'ABC1D23'
      ..items = [BudgetItem(description: 'Porta', op: ItemOp.troca, price: 900)];
    a.touch(ca);
    a.upsertContact(Contact(kind: ContactKind.cliente, name: 'João Silva', phone: '11 99999-0000'));
    final lixaA = StockItem(kind: StockKind.material, name: 'Lixa P320', unit: 'folha', qty: 40, cost: 1.2);
    a.upsertStock(lixaA);
    a.upsertEntry(FinanceEntry(description: 'Pagamento Carlos', isIncome: true, amount: 900, claimId: ca.id));
    // nota guardada no A, ligada à lixa do A
    final nota = parseReceipt(const [
      'LOJA DO PINTOR',
      'LIXA P320 10 FL 1,20 12,00',
      'TOTAL 12,00',
    ]);
    await a.registerPurchase(nota, lines: planStockEntry(nota, a.stock), toFinance: true);
    a.settings.shopName = 'Oficina do A';
    a.changed();
    final zip = await a.exportBackup();

    // --- aparelho B (já tem dados próprios)
    final b = await openStore();
    final cb = b.newClaim()
      ..customerName = 'Beatriz'
      ..vehicle.plate = 'XYZ9K87'
      ..items = [BudgetItem(description: 'Capô', op: ItemOp.pintura, paintHours: 3)];
    b.touch(cb);
    expect(cb.number, ca.number); // os dois criaram o mesmo número
    b.upsertContact(Contact(kind: ContactKind.cliente, name: 'joão silva', email: 'joao@ex.com'));
    final lixaB = StockItem(kind: StockKind.material, name: 'LIXA P320', unit: 'folha', qty: 3, cost: 1);
    b.upsertStock(lixaB);
    b.upsertStock(StockItem(kind: StockKind.peca, name: 'Farol Gol G5', qty: 1, cost: 300));
    b.settings.shopName = 'Oficina do B';
    b.changed();

    final r = await b.importBackup(zip);
    expect(r.fullRestore, isFalse);

    // orçamentos: os dois ficam; o do backup ganhou número novo
    expect(b.claims.length, 2);
    final beatriz = b.claims.firstWhere((c) => c.customerName == 'Beatriz');
    final carlos = b.claims.firstWhere((c) => c.customerName == 'Carlos');
    expect(beatriz.number, cb.number);
    expect(carlos.number, isNot(cb.number));
    expect(carlos.id, ca.id);
    expect(carlos.items.single.price, 900);
    expect(r.added['claims'], 1);

    // cadastro igual (mesmo nome) não duplica: completa com o telefone
    final joao = b.contacts.where((c) => c.name.toLowerCase() == 'joão silva').toList();
    expect(joao.length, 1);
    expect(joao.single.phone, '11 99999-0000');
    expect(joao.single.email, 'joao@ex.com'); // o daqui não some

    // estoque: a lixa (mesmo nome) é atualizada; o farol daqui continua
    final lixas = b.stock.where((s) => s.name.toUpperCase() == 'LIXA P320').toList();
    expect(lixas.length, 1);
    expect(lixas.single.id, lixaB.id);
    expect(lixas.single.qty, lixaA.qty); // valor do backup
    expect(b.stock.any((s) => s.name == 'Farol Gol G5'), isTrue);
    expect(r.updated['stock'], 1);

    // ligações do backup apontam para os registros daqui
    final doc = b.docs.single;
    expect(doc.items.single.stockId, lixaB.id);
    expect(lixas.single.ins.single.docId, doc.id);
    final pay = b.entries.firstWhere((e) => e.description == 'Pagamento Carlos');
    expect(pay.claimId, carlos.id);

    // ajustes daqui ficam; o próximo número passa de todos
    expect(b.settings.shopName, 'Oficina do B');
    final numbers = b.claims.map((c) => int.parse(c.number.split('-').last)).toList();
    expect(b.settings.nextNumber, greaterThan(numbers.reduce((x, y) => x > y ? x : y)));

    expect(r.summary(), contains('Mesclado'));

    // importar o mesmo backup de novo não duplica nada
    final again = await b.importBackup(zip);
    expect(again.totalAdded, 0);
    expect(b.claims.length, 2);
    expect(b.stock.where((s) => s.name.toUpperCase() == 'LIXA P320').length, 1);
    expect(b.contacts.where((c) => c.name.toLowerCase() == 'joão silva').length, 1);
    expect(b.docs.length, 1);
    expect(b.entries.where((e) => e.description == 'Pagamento Carlos').length, 1);

    // reabrir mantém tudo
    await b.flush();
    final b2 = await AppStore.open(assumeLicense: License.full(), dir: b.baseDir);
    expect(b2.claims.length, 2);
    expect(b2.docs.single.items.single.stockId, lixaB.id);
    a.dispose();
    b.dispose();
  });

  test('o que foi alterado aqui depois do backup não volta atrás', () async {
    final a = await openStore();
    final c = a.newClaim()..customerName = 'Ana';
    a.touch(c);
    final zip = await a.exportBackup();
    // mesmo aparelho: o orçamento muda depois do backup
    await Future<void>.delayed(const Duration(milliseconds: 5));
    c.customerName = 'Ana Paula';
    a.touch(c);
    final r = await a.importBackup(zip);
    expect(a.claims.single.customerName, 'Ana Paula');
    expect(r.totalAdded, 0);
    a.dispose();
  });

  test('aparelho vazio: o backup vem inteiro (com os ajustes)', () {
    final (out, r) = mergeBackupJson(
      {'settings': {'shopName': ''}, 'claims': [], 'users': [{'id': 'u1', 'name': 'Admin'}]},
      {
        'settings': {'shopName': 'Oficina X'},
        'claims': [{'id': 'c1', 'number': 'FN-0001'}],
        'users': [{'id': 'u9', 'name': 'Admin'}],
      },
    );
    expect(r.fullRestore, isTrue);
    expect((out['settings'] as Map)['shopName'], 'Oficina X');
    expect((out['claims'] as List).length, 1);
    expect((out['users'] as List).length, 1); // mesmo nome: não duplica
  });
}
