import 'models.dart';

/// Regiões do veículo usadas no mapa de avarias.
class CarRegion {
  final String id;
  final String label;

  /// Retângulo normalizado (0..1) no desenho do carro visto de cima.
  final double left, top, width, height;

  /// Itens sugeridos quando a região é marcada (descrição, operação).
  final List<(String, ItemOp)> suggestions;

  const CarRegion(this.id, this.label, this.left, this.top, this.width,
      this.height, this.suggestions);
}

// Carro desenhado de cima, frente para cima. x: 0 esquerda .. 1 direita.
const carRegions = <CarRegion>[
  CarRegion('parachoque_d', 'Para-choque dianteiro', 0.18, 0.02, 0.64, 0.07, [
    ('Para-choque dianteiro', ItemOp.troca),
    ('Para-choque dianteiro', ItemOp.pintura),
  ]),
  CarRegion('farol_e', 'Farol esquerdo', 0.18, 0.09, 0.16, 0.05, [
    ('Farol esquerdo', ItemOp.troca),
  ]),
  CarRegion('farol_d', 'Farol direito', 0.66, 0.09, 0.16, 0.05, [
    ('Farol direito', ItemOp.troca),
  ]),
  CarRegion('capo', 'Capô', 0.30, 0.10, 0.40, 0.17, [
    ('Capô', ItemOp.reparo),
    ('Capô', ItemOp.pintura),
  ]),
  CarRegion('paralama_de', 'Para-lama dianteiro esq.', 0.16, 0.14, 0.14, 0.15, [
    ('Para-lama dianteiro esquerdo', ItemOp.reparo),
    ('Para-lama dianteiro esquerdo', ItemOp.pintura),
  ]),
  CarRegion('paralama_dd', 'Para-lama dianteiro dir.', 0.70, 0.14, 0.14, 0.15, [
    ('Para-lama dianteiro direito', ItemOp.reparo),
    ('Para-lama dianteiro direito', ItemOp.pintura),
  ]),
  CarRegion('parabrisa', 'Para-brisa', 0.30, 0.27, 0.40, 0.08, [
    ('Para-brisa', ItemOp.troca),
  ]),
  CarRegion('retrovisor_e', 'Retrovisor esquerdo', 0.04, 0.30, 0.12, 0.05, [
    ('Retrovisor externo esquerdo', ItemOp.troca),
  ]),
  CarRegion('retrovisor_d', 'Retrovisor direito', 0.84, 0.30, 0.12, 0.05, [
    ('Retrovisor externo direito', ItemOp.troca),
  ]),
  CarRegion('porta_de', 'Porta dianteira esq.', 0.16, 0.30, 0.14, 0.17, [
    ('Porta dianteira esquerda', ItemOp.reparo),
    ('Porta dianteira esquerda', ItemOp.pintura),
  ]),
  CarRegion('porta_dd', 'Porta dianteira dir.', 0.70, 0.30, 0.14, 0.17, [
    ('Porta dianteira direita', ItemOp.reparo),
    ('Porta dianteira direita', ItemOp.pintura),
  ]),
  CarRegion('teto', 'Teto', 0.30, 0.35, 0.40, 0.25, [
    ('Teto', ItemOp.reparo),
    ('Teto', ItemOp.pintura),
  ]),
  CarRegion('porta_te', 'Porta traseira esq.', 0.16, 0.47, 0.14, 0.16, [
    ('Porta traseira esquerda', ItemOp.reparo),
    ('Porta traseira esquerda', ItemOp.pintura),
  ]),
  CarRegion('porta_td', 'Porta traseira dir.', 0.70, 0.47, 0.14, 0.16, [
    ('Porta traseira direita', ItemOp.reparo),
    ('Porta traseira direita', ItemOp.pintura),
  ]),
  CarRegion('vidro_t', 'Vidro traseiro', 0.30, 0.60, 0.40, 0.07, [
    ('Vidro traseiro', ItemOp.troca),
  ]),
  CarRegion('lateral_te', 'Lateral traseira esq.', 0.16, 0.63, 0.14, 0.17, [
    ('Lateral traseira esquerda', ItemOp.reparo),
    ('Lateral traseira esquerda', ItemOp.pintura),
  ]),
  CarRegion('lateral_td', 'Lateral traseira dir.', 0.70, 0.63, 0.14, 0.17, [
    ('Lateral traseira direita', ItemOp.reparo),
    ('Lateral traseira direita', ItemOp.pintura),
  ]),
  CarRegion('tampa', 'Tampa traseira / porta-malas', 0.30, 0.67, 0.40, 0.15, [
    ('Tampa traseira', ItemOp.reparo),
    ('Tampa traseira', ItemOp.pintura),
  ]),
  CarRegion('lanterna_e', 'Lanterna esquerda', 0.18, 0.82, 0.16, 0.05, [
    ('Lanterna traseira esquerda', ItemOp.troca),
  ]),
  CarRegion('lanterna_d', 'Lanterna direita', 0.66, 0.82, 0.16, 0.05, [
    ('Lanterna traseira direita', ItemOp.troca),
  ]),
  CarRegion('parachoque_t', 'Para-choque traseiro', 0.18, 0.87, 0.64, 0.08, [
    ('Para-choque traseiro', ItemOp.troca),
    ('Para-choque traseiro', ItemOp.pintura),
  ]),
];

CarRegion? regionById(String id) {
  for (final r in carRegions) {
    if (r.id == id) return r;
  }
  return null;
}

const severityLabels = {1: 'Leve', 2: 'Média', 3: 'Pesada'};

/// Horas sugeridas por operação e severidade (ponto de partida editável).
double suggestedLaborHours(ItemOp op, int severity) {
  switch (op) {
    case ItemOp.troca:
      return 1.0;
    case ItemOp.reparo:
      return [0, 1.5, 3.0, 5.0][severity.clamp(1, 3)].toDouble();
    case ItemOp.pintura:
      return 0;
    case ItemOp.servico:
      return 1;
  }
}

double suggestedPaintHours(ItemOp op, int severity) =>
    op == ItemOp.pintura ? [0, 2.0, 3.0, 4.0][severity.clamp(1, 3)].toDouble() : 0;

List<CatalogItem> defaultCatalog() => [
      CatalogItem(description: 'Para-choque dianteiro', op: ItemOp.troca, laborHours: 1.5, region: 'parachoque_d'),
      CatalogItem(description: 'Para-choque traseiro', op: ItemOp.troca, laborHours: 1.5, region: 'parachoque_t'),
      CatalogItem(description: 'Grade do radiador', op: ItemOp.troca, laborHours: 0.5),
      CatalogItem(description: 'Farol esquerdo', op: ItemOp.troca, laborHours: 0.8, region: 'farol_e'),
      CatalogItem(description: 'Farol direito', op: ItemOp.troca, laborHours: 0.8, region: 'farol_d'),
      CatalogItem(description: 'Lanterna traseira esquerda', op: ItemOp.troca, laborHours: 0.5, region: 'lanterna_e'),
      CatalogItem(description: 'Lanterna traseira direita', op: ItemOp.troca, laborHours: 0.5, region: 'lanterna_d'),
      CatalogItem(description: 'Retrovisor externo', op: ItemOp.troca, laborHours: 0.5),
      CatalogItem(description: 'Para-brisa', op: ItemOp.troca, laborType: LaborType.vidracaria, laborHours: 1.5, region: 'parabrisa'),
      CatalogItem(description: 'Radiador', op: ItemOp.troca, laborType: LaborType.mecanica, laborHours: 2),
      CatalogItem(description: 'Condensador do ar-condicionado', op: ItemOp.troca, laborType: LaborType.mecanica, laborHours: 2),
      CatalogItem(description: 'Alinhamento e balanceamento', op: ItemOp.servico, laborType: LaborType.mecanica, price: 120),
      CatalogItem(description: 'Carga de gás do ar-condicionado', op: ItemOp.servico, laborType: LaborType.mecanica, price: 250),
      CatalogItem(description: 'Polimento e cristalização', op: ItemOp.servico, price: 350),
      CatalogItem(description: 'Martelinho de ouro', op: ItemOp.servico, price: 200),
      CatalogItem(description: 'Capô', op: ItemOp.pintura, paintHours: 3, region: 'capo'),
      CatalogItem(description: 'Porta (pintura)', op: ItemOp.pintura, paintHours: 2.5),
      CatalogItem(description: 'Para-lama (pintura)', op: ItemOp.pintura, paintHours: 2),
      CatalogItem(description: 'Teto (pintura)', op: ItemOp.pintura, paintHours: 3.5, region: 'teto'),
      CatalogItem(description: 'Diagnóstico com scanner', op: ItemOp.servico, laborType: LaborType.eletrica, price: 150),
    ];
