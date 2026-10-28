import 'models.dart';

/// Valores calculados de uma linha do orçamento.
class ItemValues {
  final double parts;
  final double labor;
  final double paintLabor;
  final double paintMaterial;
  final double services;

  const ItemValues({
    this.parts = 0,
    this.labor = 0,
    this.paintLabor = 0,
    this.paintMaterial = 0,
    this.services = 0,
  });

  double get total => parts + labor + paintLabor + paintMaterial + services;
}

ItemValues itemValues(BudgetItem it, Settings s) {
  final factor = 1 - (it.discountPct.clamp(0, 100) / 100);
  final qty = it.qty <= 0 ? 1.0 : it.qty;
  final parts = it.op == ItemOp.troca ? it.price * qty * factor : 0.0;
  final services = it.op == ItemOp.servico ? it.price * qty * factor : 0.0;
  final labor = it.laborHours * s.rateFor(it.laborType);
  final paintLabor = it.paintHours * s.paintRate;
  final paintMaterial = it.paintHours * s.paintMaterialRate;
  return ItemValues(
    parts: parts,
    labor: labor,
    paintLabor: paintLabor,
    paintMaterial: paintMaterial,
    services: services,
  );
}

/// Totais do orçamento de um sinistro.
class BudgetTotals {
  final double parts;
  final double labor;
  final double paintLabor;
  final double paintMaterial;
  final double services;
  final double extra;
  final double discount;
  final double total;
  final double deductible;
  final double insurerPays;
  final double customerPays;
  final double laborHours;
  final double paintHours;
  final int itemCount;
  final int rejectedCount;

  /// Percentual do orçamento em relação ao valor FIPE (0 se sem FIPE).
  final double fipePct;
  final bool possibleTotalLoss;

  const BudgetTotals({
    required this.parts,
    required this.labor,
    required this.paintLabor,
    required this.paintMaterial,
    required this.services,
    required this.extra,
    required this.discount,
    required this.total,
    required this.deductible,
    required this.insurerPays,
    required this.customerPays,
    required this.laborHours,
    required this.paintHours,
    required this.itemCount,
    required this.rejectedCount,
    required this.fipePct,
    required this.possibleTotalLoss,
  });

  double get subtotal =>
      parts + labor + paintLabor + paintMaterial + services + extra;
}

BudgetTotals computeTotals(Claim c, Settings s, {bool onlyApproved = true}) {
  double parts = 0, labor = 0, paintLabor = 0, paintMat = 0, services = 0;
  double lh = 0, ph = 0;
  int count = 0, rejected = 0;
  for (final it in c.items) {
    if (!it.approved) {
      rejected++;
      if (onlyApproved) continue;
    }
    count++;
    final v = itemValues(it, s);
    parts += v.parts;
    labor += v.labor;
    paintLabor += v.paintLabor;
    paintMat += v.paintMaterial;
    services += v.services;
    lh += it.laborHours;
    ph += it.paintHours;
  }
  final extra = c.extraCosts < 0 ? 0.0 : c.extraCosts;
  final subtotal = parts + labor + paintLabor + paintMat + services + extra;
  final discount = subtotal * (c.discountPct.clamp(0, 100) / 100);
  final total = _round(subtotal - discount);

  final hasInsurer =
      c.type == ClaimType.seguradora || c.type == ClaimType.terceiro;
  double deductible = 0;
  if (c.type == ClaimType.seguradora) {
    deductible = c.deductible.clamp(0, total).toDouble();
  }
  final insurerPays = hasInsurer ? _round(total - deductible) : 0.0;
  final customerPays = hasInsurer ? _round(deductible) : total;

  final fipe = c.vehicle.fipeValue;
  final pct = fipe > 0 ? total / fipe * 100 : 0.0;

  return BudgetTotals(
    parts: _round(parts),
    labor: _round(labor),
    paintLabor: _round(paintLabor),
    paintMaterial: _round(paintMat),
    services: _round(services),
    extra: _round(extra),
    discount: _round(discount),
    total: total,
    deductible: _round(deductible),
    insurerPays: insurerPays,
    customerPays: customerPays,
    laborHours: lh,
    paintHours: ph,
    itemCount: count,
    rejectedCount: rejected,
    fipePct: pct,
    possibleTotalLoss: fipe > 0 && pct >= s.totalLossPct,
  );
}

double _round(double v) => (v * 100).roundToDouble() / 100;
