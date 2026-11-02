/// Resultado de cada funcionário no período: material que usou, quanto
/// recebeu pelos carros, quanto os serviços dele valeram no orçamento e o
/// lucro que gerou.
library;

import 'calc.dart';
import 'finance.dart';
import 'models.dart';

/// Um carro concluído em que o funcionário trabalhou.
class WorkerCar {
  WorkerCar(this.claim, this.role, this.revenue, this.pay, this.material);
  final Claim claim;
  final OutsourcedService role;
  final double revenue; // valor dos serviços dele no orçamento
  final double pay; // quanto ele recebe por esse carro
  final double material; // insumos que ele usou nesse carro
  double get profit => revenue - pay - material;
}

class WorkerReport {
  WorkerReport(this.name, this.worker);
  final String name;
  final Contact? worker;
  final List<WorkerCar> cars = [];
  final Set<OutsourcedService> roles = {};

  /// Material liberado para ele no período (pela data da saída).
  double material = 0;
  int materialCount = 0;

  double get revenue => cars.fold(0.0, (a, c) => a + c.revenue);
  double get pay => cars.fold(0.0, (a, c) => a + c.pay);

  /// Lucro gerado = serviços dele − pagamento dele − material dele.
  double get profit => revenue - pay - material;
  double get marginPct => revenue > 0 ? profit / revenue * 100 : 0;

  bool get salaried =>
      worker != null && !worker!.outsourced && worker!.payType == PayType.salario;
}

/// Carro concluído (ou entregue) dentro do período.
bool _concludedIn(Claim c, Period p) =>
    (c.status == ClaimStatus.concluido || c.status == ClaimStatus.entregue) &&
    p.contains(c.concludedAt ?? c.updatedAt);

/// Parte do valor de uma peça cobrada por peça (reparo + pintura juntos):
/// metade para cada um quando a peça tem os dois.
double _pieceShare(BudgetItem it, ItemValues v, bool paint) {
  if (!it.perPiece || v.pieceLabor == 0) return 0;
  final both = it.hasPaint && it.hasLabor;
  if (paint) return it.hasPaint ? v.pieceLabor * (both ? .5 : 1) : 0;
  return it.hasLabor ? v.pieceLabor * (both ? .5 : 1) : 0;
}

/// Quanto os serviços de uma função valem no orçamento do carro.
double roleRevenue(Claim c, OutsourcedService role, Settings s) {
  LaborType? labor = switch (role) {
    OutsourcedService.funilaria => LaborType.funilaria,
    OutsourcedService.mecanica => LaborType.mecanica,
    OutsourcedService.eletrica => LaborType.eletrica,
    OutsourcedService.tapecaria => LaborType.tapecaria,
    OutsourcedService.vidracaria => LaborType.vidracaria,
    _ => null,
  };
  var total = 0.0;
  for (final it in c.items) {
    if (!it.approved || it.op == ItemOp.servico) continue;
    final v = itemValues(it, s);
    if (role == OutsourcedService.pintura) {
      total += v.paintLabor + v.paintMaterial + _pieceShare(it, v, true);
    } else if (labor != null && it.laborType == labor) {
      total += v.labor + _pieceShare(it, v, false);
    }
  }
  return total;
}

/// Relatório da equipe no período.
List<WorkerReport> teamReport({
  required List<Claim> claims,
  required List<Contact> contacts,
  required Settings settings,
  required Period period,
}) {
  final byKey = <String, WorkerReport>{};
  Contact? contact(String id) =>
      id.isEmpty ? null : contacts.where((c) => c.id == id).firstOrNull;
  WorkerReport report(String id, String name) {
    final w = contact(id);
    final key = w?.id ?? (name.trim().isEmpty ? '' : 'nome:${name.trim().toLowerCase()}');
    return byKey.putIfAbsent(
        key, () => WorkerReport(w?.name ?? (name.trim().isEmpty ? 'Sem funcionário' : name.trim()), w));
  }

  for (final w in contacts.where((c) => c.kind == ContactKind.funcionario)) {
    report(w.id, w.name);
  }

  // material: saídas de insumo no período, por quem recebeu
  for (final c in claims) {
    for (final u in c.supplies) {
      if (!period.contains(u.date)) continue;
      final r = report(u.workerId, u.workerName);
      r.material += u.total;
      r.materialCount++;
    }
  }

  // serviços e pagamento: carros concluídos no período
  for (final c in claims.where((c) => _concludedIn(c, period))) {
    final sameRole = <OutsourcedService, int>{};
    for (final m in c.crew) {
      sameRole[m.role] = (sameRole[m.role] ?? 0) + 1;
    }
    for (final m in c.crew) {
      final w = contact(m.contactId);
      if (w == null) continue;
      final r = report(w.id, w.name);
      r.roles.add(m.role);
      final revenue = roleRevenue(c, m.role, settings) / sameRole[m.role]!;
      final pay = crewCost(c, m, w).amount;
      final mat = c.supplies
          .where((u) => u.workerId == w.id)
          .fold(0.0, (a, u) => a + u.total);
      r.cars.add(WorkerCar(c, m.role, revenue, pay, mat));
    }
  }

  final list = byKey.values
      .where((r) => r.cars.isNotEmpty || r.material > 0)
      .toList()
    ..sort((a, b) => b.profit.compareTo(a.profit));
  return list;
}
