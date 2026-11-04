/// Inspeção 3D: peças do carro, tipos de avaria, gravidades e os serviços
/// sugeridos (com preço e tempo que acompanham a gravidade).
library;

import 'models.dart';

/// Carroceria do modelo 3D.
enum CarBody {
  sedan('Sedã'),
  hatch('Hatch'),
  suv('SUV'),
  picape('Picape');

  const CarBody(this.label);
  final String label;

  static CarBody of(Vehicle v) {
    for (final b in CarBody.values) {
      if (b.name == v.body) return b;
    }
    return guess(v.model);
  }

  /// Palpite pela descrição do modelo (o usuário pode trocar na tela).
  static CarBody guess(String model) {
    final m = ' ${model.toLowerCase()} ';
    bool any(List<String> w) => w.any(m.contains);
    if (any([' strada', ' toro', ' hilux', ' s10', ' ranger', ' amarok', ' saveiro', ' montana', ' frontier', ' l200', ' f-150', ' f150', ' maverick', ' oroch', ' ram ', ' triton', ' picape', ' pick'])) {
      return CarBody.picape;
    }
    if (any([' suv', ' compass', ' renegade', ' creta', ' hr-v', ' hrv', ' t-cross', ' tcross', ' tracker', ' kicks', ' duster', ' ecosport', ' tiguan', ' sw4', ' rav4', ' corolla cross', ' pulse', ' fastback', ' nivus', ' taos', ' commander', ' territory', ' tucson', ' sportage', ' xc60', ' xc40', ' 2008', ' 3008', ' c4 cactus', ' outlander', ' song', ' yuan', ' haval', ' tiggo'])) {
      return CarBody.suv;
    }
    if (any([' gol ', ' polo ', ' golf', ' up ', ' onix ', ' hb20 ', ' argo', ' mobi', ' uno', ' palio', ' fox', ' sandero', ' kwid', ' ka ', ' fiesta', ' march', ' c3', ' 208', ' yaris ', ' etios ', ' celta', ' corsa', ' fit', ' i30', ' dolphin', ' hatch'])) {
      return CarBody.hatch;
    }
    return CarBody.sedan;
  }
}

/// Grupo da peça (define os serviços sugeridos).
enum PartGroup {
  lataria('Lataria'),
  parachoque('Para-choque'),
  vidro('Vidro'),
  farol('Farol / lanterna'),
  retrovisor('Retrovisor'),
  grade('Grade');

  const PartGroup(this.label);
  final String label;
}

class CarPart {
  const CarPart(this.id, this.label, this.group, {this.side = ''});
  final String id;
  final String label;
  final PartGroup group;

  /// "Lado esquerdo", "Lado direito", "Frente", "Traseira", "Topo".
  final String side;

  LaborType get laborType => switch (group) {
        PartGroup.vidro => LaborType.vidracaria,
        PartGroup.farol => LaborType.eletrica,
        _ => LaborType.funilaria,
      };
}

const _esq = 'Lado esquerdo', _dir = 'Lado direito';

/// Peças clicáveis do modelo 3D (a picape troca a tampa e a lateral traseira
/// pela caçamba).
List<CarPart> partsFor(CarBody body) {
  final pick = body == CarBody.picape;
  return [
    const CarPart('parachoque_d', 'Para-choque dianteiro', PartGroup.parachoque, side: 'Frente'),
    const CarPart('grade', 'Grade dianteira', PartGroup.grade, side: 'Frente'),
    const CarPart('farol_e', 'Farol esquerdo', PartGroup.farol, side: 'Frente'),
    const CarPart('farol_d', 'Farol direito', PartGroup.farol, side: 'Frente'),
    const CarPart('capo', 'Capô', PartGroup.lataria, side: 'Frente'),
    const CarPart('parabrisa', 'Para-brisa', PartGroup.vidro, side: 'Frente'),
    const CarPart('teto', 'Teto', PartGroup.lataria, side: 'Topo'),
    const CarPart('paralama_de', 'Para-lama dianteiro esquerdo', PartGroup.lataria, side: _esq),
    const CarPart('paralama_dd', 'Para-lama dianteiro direito', PartGroup.lataria, side: _dir),
    const CarPart('porta_de', 'Porta dianteira esquerda', PartGroup.lataria, side: _esq),
    const CarPart('porta_dd', 'Porta dianteira direita', PartGroup.lataria, side: _dir),
    const CarPart('porta_te', 'Porta traseira esquerda', PartGroup.lataria, side: _esq),
    const CarPart('porta_td', 'Porta traseira direita', PartGroup.lataria, side: _dir),
    const CarPart('retrovisor_e', 'Retrovisor esquerdo', PartGroup.retrovisor, side: _esq),
    const CarPart('retrovisor_d', 'Retrovisor direito', PartGroup.retrovisor, side: _dir),
    CarPart('lateral_te', pick ? 'Lateral da caçamba esquerda' : 'Lateral traseira esquerda',
        PartGroup.lataria, side: _esq),
    CarPart('lateral_td', pick ? 'Lateral da caçamba direita' : 'Lateral traseira direita',
        PartGroup.lataria, side: _dir),
    if (pick)
      const CarPart('cacamba', 'Caçamba', PartGroup.lataria, side: 'Traseira'),
    if (body == CarBody.sedan || pick)
      const CarPart('vigia', 'Vidro traseiro', PartGroup.vidro, side: 'Traseira'),
    CarPart(
        'tampa',
        switch (body) {
          CarBody.sedan => 'Tampa do porta-malas',
          CarBody.picape => 'Tampa da caçamba',
          _ => 'Tampa traseira',
        },
        PartGroup.lataria,
        side: 'Traseira'),
    const CarPart('lanterna_e', 'Lanterna traseira esquerda', PartGroup.farol, side: 'Traseira'),
    const CarPart('lanterna_d', 'Lanterna traseira direita', PartGroup.farol, side: 'Traseira'),
    const CarPart('parachoque_t', 'Para-choque traseiro', PartGroup.parachoque, side: 'Traseira'),
  ];
}

CarPart? partById(CarBody body, String id) {
  for (final p in partsFor(body)) {
    if (p.id == id) return p;
  }
  return null;
}

/// Nome da peça mesmo que ela não exista nessa carroceria.
String partLabel(String id) {
  for (final b in CarBody.values) {
    final p = partById(b, id);
    if (p != null) return p.label;
  }
  return id;
}

/// Tipos de avaria.
const damageTypes = <(String, String)>[
  ('amassado', 'Amassado'),
  ('risco', 'Risco'),
  ('trinca', 'Trinca'),
  ('quebra', 'Quebra'),
  ('corrosao', 'Corrosão'),
  ('pintura', 'Pintura danificada'),
];

String damageTypeLabel(String id) {
  for (final (k, l) in damageTypes) {
    if (k == id) return l;
  }
  return id.isEmpty ? 'Serviço sem avaria' : id;
}

/// Gravidade: nome, explicação e fator de preço/tempo.
const severities = <int, (String, String, double)>{
  1: ('Leve', 'Estético, sem comprometer a peça', 1.0),
  2: ('Moderada', 'Afeta o acabamento e pede reparo com pintura', 1.3),
  3: ('Grave', 'Compromete a peça: troca ou reparo pesado', 1.7),
};

String severityName(int s) => severities[s.clamp(1, 3)]!.$1;

/// Prazo em dias úteis (8 h por dia).
int workDays(int minutes) => minutes <= 0 ? 0 : ((minutes / 60) / 8).ceil();

/// "11h 12min"
String hoursText(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}min';
  return m == 0 ? '${h}h' : '${h}h ${m}min';
}

/// Serviço do catálogo da Inspeção 3D (editável nos Ajustes do catálogo).
class ServiceTemplate {
  String id;
  String name;
  String category; // Funilaria, Pintura, Vidros, Elétrica, Estética, Peças…
  Set<PartGroup> groups; // vazio = qualquer peça
  Set<String> types; // vazio = qualquer tipo de avaria
  int minSeverity;
  double price; // valor na gravidade leve
  int minutes; // tempo na gravidade leve
  bool followsSeverity;
  bool isPart;

  ServiceTemplate({
    String? id,
    this.name = '',
    this.category = 'Funilaria',
    Set<PartGroup>? groups,
    Set<String>? types,
    this.minSeverity = 1,
    this.price = 0,
    this.minutes = 0,
    this.followsSeverity = true,
    this.isPart = false,
  })  : id = id ?? newId(),
        groups = groups ?? {},
        types = types ?? {};

  bool appliesTo(CarPart part, String type, int severity) =>
      (groups.isEmpty || groups.contains(part.group)) &&
      (type.isEmpty || types.isEmpty || types.contains(type)) &&
      severity >= minSeverity;

  InspectionService forSeverity(int severity) {
    final f = followsSeverity ? severities[severity.clamp(1, 3)]!.$3 : 1.0;
    return InspectionService(
      name: name,
      price: (price * f / 5).round() * 5.0, // arredonda de 5 em 5
      minutes: (minutes * f).round(),
      isPart: isPart,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cat': category,
        'groups': groups.map((e) => e.name).toList(),
        'types': types.toList(),
        'minSev': minSeverity,
        'price': price,
        'min': minutes,
        'sev': followsSeverity,
        if (isPart) 'part': true,
      };

  factory ServiceTemplate.fromJson(Map<String, dynamic> j) => ServiceTemplate(
        id: '${j['id'] ?? newId()}',
        name: '${j['name'] ?? ''}',
        category: '${j['cat'] ?? 'Funilaria'}',
        groups: {
          for (final g in (j['groups'] is List ? j['groups'] as List : const []))
            for (final pg in PartGroup.values)
              if (pg.name == g) pg
        },
        types: {
          for (final t in (j['types'] is List ? j['types'] as List : const [])) '$t'
        },
        minSeverity: (j['minSev'] is num ? (j['minSev'] as num).toInt() : 1).clamp(1, 3),
        price: j['price'] is num ? (j['price'] as num).toDouble() : 0,
        minutes: j['min'] is num ? (j['min'] as num).toInt() : 0,
        followsSeverity: j['sev'] != false,
        isPart: j['part'] == true,
      );
}

const serviceCategories = ['Funilaria', 'Pintura', 'Vidros', 'Elétrica', 'Estética', 'Peças', 'Mecânica'];

/// Catálogo inicial (valores de exemplo; a oficina ajusta).
List<ServiceTemplate> defaultInspectionServices() {
  const lat = {PartGroup.lataria, PartGroup.parachoque};
  ServiceTemplate t(String name, String cat, Set<PartGroup> g, double price, int min,
          {Set<String>? types, int minSev = 1, bool sev = true, bool part = false}) =>
      ServiceTemplate(
          id: 'svc_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}',
          name: name,
          category: cat,
          groups: {...g},
          types: types,
          minSeverity: minSev,
          price: price,
          minutes: min,
          followsSeverity: sev,
          isPart: part);
  return [
    t('Recuperação e pintura', 'Funilaria', lat, 700, 300),
    t('Recuperação (desamassar)', 'Funilaria', lat, 410, 180,
        types: {'amassado', 'quebra', 'corrosao'}),
    t('Martelinho de ouro', 'Funilaria', {PartGroup.lataria}, 240, 90,
        types: {'amassado'}),
    t('Pintura da peça', 'Pintura', lat, 430, 180),
    t('Retoque de pintura', 'Pintura', lat, 190, 60,
        types: {'risco', 'pintura'}),
    t('Polimento técnico', 'Estética', lat, 150, 60,
        types: {'risco', 'pintura'}),
    t('Tratamento de corrosão', 'Funilaria', lat, 260, 120,
        types: {'corrosao'}),
    t('Reparo de plástico (solda)', 'Funilaria', {PartGroup.parachoque}, 220, 90,
        types: {'trinca', 'quebra'}),
    t('Substituição da peça (mão de obra)', 'Funilaria',
        {...lat, PartGroup.grade, PartGroup.retrovisor}, 250, 120,
        minSev: 3),
    t('Insumos de pintura', 'Peças', lat, 80, 0, part: true),
    t('Reparo de trinca no vidro', 'Vidros', {PartGroup.vidro}, 150, 45,
        types: {'trinca', 'risco'}),
    t('Substituição do vidro (mão de obra)', 'Vidros', {PartGroup.vidro}, 280, 120,
        minSev: 2),
    t('Polimento de farol', 'Estética', {PartGroup.farol}, 120, 40,
        types: {'risco', 'pintura'}),
    t('Substituição de farol/lanterna (mão de obra)', 'Elétrica',
        {PartGroup.farol}, 90, 40,
        types: {'trinca', 'quebra'}),
    t('Capa do retrovisor (mão de obra)', 'Funilaria', {PartGroup.retrovisor}, 90, 30),
    t('Diagnóstico', 'Mecânica', {}, 100, 30, sev: false),
    t('Lavagem técnica', 'Estética', {}, 150, 60, sev: false),
  ];
}

/// Serviços sugeridos para a peça, o tipo e a gravidade.
List<(ServiceTemplate, InspectionService)> suggestedServices(
    List<ServiceTemplate> catalog, CarPart part, String type, int severity) =>
    [
      for (final t in catalog)
        if (t.appliesTo(part, type, severity)) (t, t.forSeverity(severity)),
    ];

/// Itens do orçamento gerados por uma avaria da inspeção.
List<BudgetItem> itemsForDamage(InspectionDamage d, CarBody body) {
  final part = partById(body, d.partId);
  final label = part?.label ?? partLabel(d.partId);
  final note = d.type.isEmpty
      ? 'Inspeção 3D'
      : 'Inspeção 3D · ${damageTypeLabel(d.type)} · ${severityName(d.severity).toLowerCase()}';
  return [
    for (final s in d.services)
      BudgetItem(
        description: '$label — ${s.name}',
        op: s.isPart ? ItemOp.troca : ItemOp.servico,
        price: s.price,
        laborType: part?.laborType ?? LaborType.funilaria,
        region: d.partId,
        inspectionId: d.id,
        note: note,
      ),
  ];
}

/// Coloca (ou atualiza) os itens da avaria no orçamento, no mesmo lugar.
void syncDamageItems(Claim c, InspectionDamage d, CarBody body) {
  final at = c.items.indexWhere((e) => e.inspectionId == d.id);
  final keepApproved = {
    for (final e in c.items.where((e) => e.inspectionId == d.id)) e.description: e.approved
  };
  c.items.removeWhere((e) => e.inspectionId == d.id);
  final fresh = itemsForDamage(d, body);
  for (final it in fresh) {
    it.approved = keepApproved[it.description] ?? true;
  }
  c.items.insertAll(at < 0 || at > c.items.length ? c.items.length : at, fresh);
}

/// Resumo da inspeção para o painel lateral.
class InspectionSummary {
  InspectionSummary(this.parts, this.labor, this.minutes);
  final double parts; // peças e insumos
  final double labor; // mão de obra
  final int minutes;
  double get total => parts + labor;
  int get days => workDays(minutes);
}

InspectionSummary summarize(Claim c) {
  var parts = 0.0, labor = 0.0, min = 0;
  for (final d in c.inspection) {
    for (final s in d.services) {
      if (s.isPart) {
        parts += s.price;
      } else {
        labor += s.price;
      }
      min += s.minutes;
    }
  }
  return InspectionSummary(parts, labor, min);
}
