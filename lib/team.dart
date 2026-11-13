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
  s = s.forClaim(c);
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
      final pay = crewCost(c, m, w, settings: settings).amount;
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

// ------------------------------------------------------------- produção
//
// Quanto cada funcionário produziu: os carros em que foi escalado, com as
// peças/serviços da função dele em cada um, nos últimos 7, 15 e 30 dias.

/// Itens do orçamento que são trabalho da função (as mesmas peças que o app
/// conta para pagar por peça).
List<BudgetItem> roleItems(Claim c, OutsourcedService role) {
  List<BudgetItem> labor(LaborType t, {bool partsOnly = false}) => c.items
      .where((i) =>
          i.approved &&
          i.hasLabor &&
          i.laborType == t &&
          (!partsOnly || i.parentId.isEmpty))
      .toList();
  return switch (role) {
    OutsourcedService.pintura => c.items.where((i) => i.approved && i.hasPaint).toList(),
    OutsourcedService.funilaria => labor(LaborType.funilaria, partsOnly: true),
    OutsourcedService.mecanica => labor(LaborType.mecanica),
    OutsourcedService.eletrica => labor(LaborType.eletrica),
    OutsourcedService.tapecaria => labor(LaborType.tapecaria),
    OutsourcedService.vidracaria => labor(LaborType.vidracaria),
    _ => const [],
  };
}

/// Um trabalho do funcionário: a função dele em um carro.
class ProductionJob {
  ProductionJob(this.claim, this.role, this.pieces, this.items, this.date, this.done);
  final Claim claim;
  final OutsourcedService role;

  /// Peças/serviços que contam para ele nesse carro.
  final double pieces;

  /// Os itens do orçamento que são dele (vazio quando a função não tem
  /// itens próprios, como martelinho e polimento).
  final List<BudgetItem> items;

  /// Concluído: data da conclusão. Em andamento: data da aprovação.
  final DateTime date;
  final bool done;
}

class WorkerProduction {
  WorkerProduction(this.name, this.worker);
  final String name;
  final Contact? worker;

  /// Carros concluídos (mais recentes primeiro) e em andamento.
  final List<ProductionJob> done = [];
  final List<ProductionJob> open = [];

  Set<OutsourcedService> get roles => {...done.map((j) => j.role), ...open.map((j) => j.role)};

  /// Concluídos nos últimos [days] dias (contando de [now]).
  List<ProductionJob> within(int days, DateTime now) {
    final from = now.subtract(Duration(days: days));
    return done.where((j) => !j.date.isBefore(from) && !j.date.isAfter(now)).toList();
  }

  double pieces(int days, DateTime now) =>
      within(days, now).fold(0.0, (a, j) => a + j.pieces);

  int cars(int days, DateTime now) =>
      within(days, now).map((j) => j.claim.id).toSet().length;

  double get openPieces => open.fold(0.0, (a, j) => a + j.pieces);
}

/// Produção de cada funcionário: carros concluídos nos últimos [maxDays]
/// dias e os que estão em andamento agora.
List<WorkerProduction> productionReport({
  required List<Claim> claims,
  required List<Contact> contacts,
  DateTime? now,
  int maxDays = 30,
}) {
  final at = now ?? DateTime.now();
  final from = at.subtract(Duration(days: maxDays));
  final byId = <String, WorkerProduction>{};
  for (final w in contacts.where((c) => c.kind == ContactKind.funcionario)) {
    byId[w.id] = WorkerProduction(w.name, w);
  }
  for (final c in claims) {
    if (c.crew.isEmpty) continue;
    final finished = c.status == ClaimStatus.concluido || c.status == ClaimStatus.entregue;
    final running = c.status == ClaimStatus.aprovado || c.status == ClaimStatus.emReparo;
    if (!finished && !running) continue;
    final date = finished ? (c.concludedAt ?? c.updatedAt) : (c.approvedAt ?? c.updatedAt);
    if (finished && (date.isBefore(from) || date.isAfter(at))) continue;
    for (final m in c.crew) {
      final r = byId[m.contactId];
      if (r == null) continue;
      final job = ProductionJob(c, m.role, crewPieces(c, m), roleItems(c, m.role), date, finished);
      (finished ? r.done : r.open).add(job);
    }
  }
  final list = byId.values.where((r) => r.done.isNotEmpty || r.open.isNotEmpty).toList();
  for (final r in list) {
    r.done.sort((a, b) => b.date.compareTo(a.date));
    r.open.sort((a, b) => b.date.compareTo(a.date));
  }
  list.sort((a, b) {
    final p = b.pieces(maxDays, at).compareTo(a.pieces(maxDays, at));
    return p != 0 ? p : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
}
