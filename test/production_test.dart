import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/models.dart';
import 'package:funilar/team.dart';

void main() {
  final now = DateTime(2026, 11, 13, 12);
  final luan = Contact(kind: ContactKind.funcionario, name: 'Luan');
  final baiano = Contact(kind: ContactKind.funcionario, name: 'Baiano');

  Claim car(String number, ClaimStatus status, {DateTime? concluded, DateTime? approved}) => Claim(
        number: number,
        status: status,
        items: [
          BudgetItem(description: 'Porta dianteira', op: ItemOp.reparo, laborHours: 2, paintHours: 2),
          BudgetItem(description: 'Para-lama', op: ItemOp.reparo, laborHours: 1, paintHours: 1),
          BudgetItem(description: 'Capô', op: ItemOp.pintura, paintHours: 3),
          BudgetItem(description: 'Teto (recusado)', op: ItemOp.pintura, paintHours: 3, approved: false),
        ],
      )
        ..crew = [
          CrewMember(role: OutsourcedService.pintura, contactId: luan.id),
          CrewMember(role: OutsourcedService.funilaria, contactId: baiano.id),
        ]
        ..concludedAt = concluded
        ..approvedAt = approved;

  test('produção por funcionário nos últimos 7, 15 e 30 dias', () {
    final claims = [
      car('FN-0001', ClaimStatus.concluido, concluded: now.subtract(const Duration(days: 2))),
      car('FN-0002', ClaimStatus.entregue, concluded: now.subtract(const Duration(days: 10))),
      car('FN-0003', ClaimStatus.concluido, concluded: now.subtract(const Duration(days: 25))),
      car('FN-0004', ClaimStatus.concluido, concluded: now.subtract(const Duration(days: 45))),
      car('FN-0005', ClaimStatus.emReparo, approved: now.subtract(const Duration(days: 1))),
      car('FN-0006', ClaimStatus.orcamento),
    ];
    final list = productionReport(claims: claims, contacts: [luan, baiano], now: now);
    expect(list.map((r) => r.name), ['Luan', 'Baiano']); // quem fez mais primeiro

    final l = list.first; // pintor: 3 peças com pintura por carro
    expect(l.pieces(7, now), 3);
    expect(l.pieces(15, now), 6);
    expect(l.pieces(30, now), 9);
    expect(l.cars(7, now), 1);
    expect(l.cars(30, now), 3);
    expect(l.within(30, now).map((j) => j.claim.number), ['FN-0001', 'FN-0002', 'FN-0003']);
    expect(l.within(7, now).single.items.map((i) => i.description),
        ['Porta dianteira', 'Para-lama', 'Capô']);
    // em andamento aparece separado e não entra na conta do período
    expect(l.open.single.claim.number, 'FN-0005');
    expect(l.openPieces, 3);

    final b = list.last; // funileiro: 2 peças com funilaria por carro
    expect(b.pieces(7, now), 2);
    expect(b.pieces(30, now), 6);
    expect(b.roles, {OutsourcedService.funilaria});
  });

  test('quantidade informada à mão na equipe vale; função sem itens conta 1', () {
    final c = car('FN-0009', ClaimStatus.concluido, concluded: now.subtract(const Duration(days: 1)));
    c.crew = [
      CrewMember(role: OutsourcedService.pintura, contactId: luan.id, pieces: 5),
      CrewMember(role: OutsourcedService.polimento, contactId: baiano.id),
    ];
    final list = productionReport(claims: [c], contacts: [luan, baiano], now: now);
    expect(list.firstWhere((r) => r.name == 'Luan').pieces(7, now), 5);
    final b = list.firstWhere((r) => r.name == 'Baiano');
    expect(b.pieces(7, now), 1);
    expect(b.within(7, now).single.items, isEmpty);
  });

  test('funcionário sem trabalho nos últimos 30 dias não aparece', () {
    final c = car('FN-0010', ClaimStatus.concluido, concluded: now.subtract(const Duration(days: 60)));
    expect(productionReport(claims: [c], contacts: [luan, baiano], now: now), isEmpty);
  });
}
