import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/finance.dart';
import 'package:funilar/models.dart';
import 'package:funilar/team.dart';

void main() {
  test('material e lucro gerado por funcionário no mês', () {
    final s = Settings(
      laborRates: {for (final l in LaborType.values) l.name: 100},
      paintRate: 90,
      paintMaterialRate: 50,
    );
    final luan = Contact(id: 'l', kind: ContactKind.funcionario, name: 'Luan', payType: PayType.porPeca, rate: 100);
    final baiano = Contact(
        id: 'b',
        kind: ContactKind.funcionario,
        name: 'Baiano',
        outsourced: true,
        service: OutsourcedService.funilaria,
        payType: PayType.empreita,
        rate: 500);
    final out = DateTime(2026, 10, 20);
    final c = Claim(number: 'FN-0001', status: ClaimStatus.concluido)
      ..concludedAt = out
      ..items = [
        BudgetItem(description: 'Capô', op: ItemOp.pintura, paintHours: 2), // pintura 180 + material 100
        BudgetItem(
            description: 'Porta',
            op: ItemOp.reparo,
            perPiece: true,
            piecePrice: 600,
            doRepair: true,
            doPaint: true), // metade pintura, metade funilaria
      ]
      ..crew = [
        CrewMember(role: OutsourcedService.pintura, contactId: 'l'),
        CrewMember(role: OutsourcedService.funilaria, contactId: 'b'),
      ]
      ..supplies = [
        SupplyUse(name: 'Lixa', qty: 10, unitCost: 3, workerId: 'l', workerName: 'Luan', date: out),
        SupplyUse(name: 'Massa', qty: 1, unitCost: 40, workerId: 'b', workerName: 'Baiano', date: out),
        SupplyUse(name: 'Fita', qty: 1, unitCost: 10, date: out),
      ];
    // carro em andamento: material conta pela data, mas serviço ainda não
    final open = Claim(number: 'FN-0002', status: ClaimStatus.emReparo)
      ..crew = [CrewMember(role: OutsourcedService.pintura, contactId: 'l')]
      ..items = [BudgetItem(description: 'Teto', op: ItemOp.pintura, paintHours: 3)]
      ..supplies = [SupplyUse(name: 'Verniz', qty: 1, unitCost: 20, workerId: 'l', workerName: 'Luan', date: out)];
    // mês seguinte não entra
    final nov = Claim(number: 'FN-0003', status: ClaimStatus.entregue)
      ..concludedAt = DateTime(2026, 11, 3)
      ..crew = [CrewMember(role: OutsourcedService.pintura, contactId: 'l')]
      ..items = [BudgetItem(description: 'Teto', op: ItemOp.pintura, paintHours: 3)];

    expect(roleRevenue(c, OutsourcedService.pintura, s), 580);
    expect(roleRevenue(c, OutsourcedService.funilaria, s), 300);

    final r = teamReport(
        claims: [c, open, nov],
        contacts: [luan, baiano],
        settings: s,
        period: Period.month(2026, 10));
    expect(r.map((e) => e.name), ['Luan', 'Sem funcionário', 'Baiano']);
    final l = r.first;
    expect(l.cars.length, 1);
    expect(l.revenue, 580);
    expect(l.pay, 200); // 2 peças pintadas × 100
    expect(l.material, 50); // lixa 30 + verniz 20 (carro em andamento)
    expect(l.profit, 330);
    expect(l.cars.single.material, 30);
    final b = r.last;
    expect(b.revenue, 300);
    expect(b.pay, 500);
    expect(b.material, 40);
    expect(b.profit, -240);
    expect(r[1].material, 10);
  });
}
