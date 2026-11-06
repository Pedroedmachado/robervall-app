import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/licensing.dart';
import 'package:funilar/finance.dart';
import 'package:funilar/models.dart';
import 'package:funilar/store.dart';

void main() {
  test('custo do pintor entra no financeiro quando o orçamento fecha', () async {
    final store = await AppStore.open(assumeLicense: License.full(), 
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
    final membro = CrewMember(role: OutsourcedService.pintura, contactId: pintor.id);
    c.crew = [membro];
    store.touch(c);
    expect(paintedPieces(c), 3);
    expect(crewCost(c, membro, pintor).amount, 105);
    // ainda em orçamento: não lança
    expect(store.entries, isEmpty);

    store.setStatus(c, ClaimStatus.aprovado);
    final e = store.entries.single;
    expect(e.autoKey, crewAutoKey);
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
    c.crew.clear();
    store.touch(c);
    expect(store.entries, isEmpty);

    // empreita: valor fixo por carro; salário: não gera custo por carro
    final emp = Contact(
        kind: ContactKind.funcionario, name: 'Zé', payType: PayType.empreita, rate: 600);
    final sal = Contact(
        kind: ContactKind.funcionario, name: 'Ana', payType: PayType.salario, rate: 2500);
    expect(crewCost(c, membro, emp).amount, 600);
    expect(crewCost(c, membro, sal).amount, 0);

    final back = Contact.fromJson(pintor.toJson());
    expect(back.payType, PayType.porPeca);
    expect(back.rate, 40);
    expect(Claim.fromJson(c.toJson()).crew, isEmpty);
  });

  test('equipe: pintor, funileiro e martelinho lançados juntos', () async {
    final store = await AppStore.open(assumeLicense: License.full(), 
        dir: await Directory.systemTemp.createTemp('funilar_equipe'));
    final pintor = Contact(
        kind: ContactKind.funcionario, name: 'Luan', payType: PayType.porPeca, rate: 100);
    final funileiro = Contact(
        kind: ContactKind.funcionario,
        name: 'Baiano',
        outsourced: true,
        service: OutsourcedService.funilaria,
        payType: PayType.empreita,
        rate: 500);
    final martelinho = Contact(
        kind: ContactKind.funcionario,
        name: 'Zé do martelinho',
        outsourced: true,
        service: OutsourcedService.martelinho,
        payType: PayType.porPeca,
        rate: 80);
    for (final w in [pintor, funileiro, martelinho]) {
      store.upsertContact(w);
    }
    final c = store.newClaim()
      ..items = [
        BudgetItem(description: 'Porta', op: ItemOp.reparo, laborHours: 3, paintHours: 3),
        BudgetItem(description: 'Para-lama', op: ItemOp.troca, laborHours: 1, paintHours: 2),
        BudgetItem(description: 'Teto', op: ItemOp.pintura, paintHours: 2),
      ];
    final mart = CrewMember(
        role: OutsourcedService.martelinho, contactId: martelinho.id, pieces: 4);
    c.crew = [
      CrewMember(role: OutsourcedService.pintura, contactId: pintor.id),
      CrewMember(role: OutsourcedService.funilaria, contactId: funileiro.id),
      mart,
    ];
    expect(autoPieces(c, OutsourcedService.pintura), 3);
    expect(autoPieces(c, OutsourcedService.funilaria), 2);
    expect(autoPieces(c, OutsourcedService.martelinho), isNull);
    store.setStatus(c, ClaimStatus.aprovado);
    expect(store.entries.length, 3);
    final byName = {for (final e in store.entries) e.contact: e};
    expect(byName['Luan']!.amount, 300);
    expect(byName['Baiano']!.amount, 500);
    expect(byName['Baiano']!.service, OutsourcedService.funilaria);
    expect(byName['Zé do martelinho']!.amount, 320);
    expect(byName['Zé do martelinho']!.description, startsWith('Martelinho de ouro'));
    expect(linkedCosts(c, store.entries), 1120);

    // valor combinado só neste carro
    mart.rate = 100;
    store.touch(c);
    expect(store.entries.firstWhere((e) => e.contact == 'Zé do martelinho').amount, 400);

    // tirar da equipe remove só o lançamento dele
    c.crew.remove(mart);
    store.touch(c);
    expect(store.entries.length, 2);

    // apagar o cadastro tira da equipe
    store.removeContact(funileiro);
    expect(c.crew.length, 1);
    expect(store.entries.single.contact, 'Luan');

    // sinistro antigo (só "painter") vira equipe com o pintor
    final old = Claim.fromJson({...c.toJson()..remove('crew'), 'painter': pintor.id});
    expect(old.crew.single.role, OutsourcedService.pintura);
    expect(old.crew.single.contactId, pintor.id);
  });

  test('comissão: % dos serviços da função dele no carro', () {
    final s = Settings(laborRates: {for (final l in LaborType.values) l.name: 100})
      ..paintRate = 80
      ..paintMaterialRate = 50;
    final c = Claim(number: 'X')
      ..items = [
        BudgetItem(description: 'Porta', op: ItemOp.reparo, laborHours: 3, paintHours: 2),
        BudgetItem(description: 'Capô', op: ItemOp.pintura, paintHours: 2),
        BudgetItem(description: 'Para-choque', op: ItemOp.troca, price: 900),
        BudgetItem(description: 'Grade', op: ItemOp.reparo, laborHours: 5, approved: false),
      ];
    final funileiro = Contact(
        kind: ContactKind.funcionario, name: 'Baiano', payType: PayType.comissao, rate: 30);
    final pintor = Contact(
        kind: ContactKind.funcionario, name: 'Luan', payType: PayType.comissao, rate: 25);
    final f = crewCost(c, CrewMember(role: OutsourcedService.funilaria, contactId: funileiro.id),
        funileiro, settings: s);
    expect(f.base, 300); // 3 h × 100 (a grade não foi aprovada; peça não entra)
    expect(f.amount, 90);
    final p = crewCost(c, CrewMember(role: OutsourcedService.pintura, contactId: pintor.id),
        pintor, settings: s);
    expect(p.base, 320); // 4 h × 80, sem o material de pintura
    expect(p.amount, 80);
    // martelinho: toda a mão de obra aprovada
    final m = crewCost(c, CrewMember(role: OutsourcedService.martelinho, contactId: funileiro.id),
        funileiro, settings: s);
    expect(m.base, 300 + 320);
    expect(PayType.values.map((e) => e.label), contains('Comissão'));
  });
}
