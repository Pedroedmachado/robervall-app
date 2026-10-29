import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/finance.dart';
import 'package:funilar/models.dart';
import 'package:funilar/store.dart';

void main() {
  test('custo do pintor entra no financeiro quando o orçamento fecha', () async {
    final store = await AppStore.open(
        dir: await Directory.systemTemp.createTemp('funilar_pintor'));
    final pintor = Contact(
        kind: ContactKind.funcionario,
        name: 'João pintor',
        payType: PayType.porPeca,
        rate: 35);
    store.upsertContact(pintor);
    final c = store.newClaim()
      ..vehicle.plate = 'ABC-1D23'
      ..items = [
        BudgetItem(description: 'Capô', op: ItemOp.troca, price: 500, paintHours: 4),
        BudgetItem(description: 'Porta', op: ItemOp.reparo, laborHours: 2, paintHours: 3),
        BudgetItem(description: 'Teto', op: ItemOp.pintura, paintHours: 2),
        BudgetItem(description: 'Farol', op: ItemOp.troca, price: 300), // sem P
        BudgetItem(description: 'Para-lama', op: ItemOp.pintura, paintHours: 2, approved: false),
      ];
    c.painterId = pintor.id;
    store.touch(c);
    expect(paintedPieces(c), 3);
    expect(painterCost(c, pintor).amount, 105);
    // ainda em orçamento: não lança
    expect(store.entries, isEmpty);

    store.setStatus(c, ClaimStatus.aprovado);
    final e = store.entries.single;
    expect(e.autoKey, painterAutoKey);
    expect(e.amount, 105);
    expect(e.pieces, 3);
    expect(e.contact, 'João pintor');
    expect(e.claimId, c.id);
    expect(e.category, ExpenseCategory.funcionario);

    // mais uma peça pintada: atualiza, sem duplicar
    c.items.add(BudgetItem(description: 'Tampa', op: ItemOp.pintura, paintHours: 3));
    store.touch(c);
    expect(store.entries.single.amount, 140);

    // valor do pintor mudou no cadastro
    pintor.rate = 40;
    store.upsertContact(pintor);
    expect(store.entries.single.amount, 160);

    // lucro do sinistro considera o custo
    expect(linkedCosts(c, store.entries), 160);

    // sem pintor ou voltando para orçamento: some
    store.setStatus(c, ClaimStatus.orcamento);
    expect(store.entries, isEmpty);
    store.setStatus(c, ClaimStatus.emReparo);
    expect(store.entries.length, 1);
    c.painterId = '';
    store.touch(c);
    expect(store.entries, isEmpty);

    // empreita: valor fixo por carro; salário: não gera custo por carro
    final emp = Contact(
        kind: ContactKind.funcionario, name: 'Zé', payType: PayType.empreita, rate: 600);
    final sal = Contact(
        kind: ContactKind.funcionario, name: 'Ana', payType: PayType.salario, rate: 2500);
    expect(painterCost(c, emp).amount, 600);
    expect(painterCost(c, sal).amount, 0);

    final back = Contact.fromJson(pintor.toJson());
    expect(back.payType, PayType.porPeca);
    expect(back.rate, 40);
    expect(Claim.fromJson(c.toJson()).painterId, '');
  });
}
