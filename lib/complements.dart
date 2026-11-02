// Peças complementares: o que precisa sair junto (R&I) ou ser trocado quando
// uma peça principal é trocada, reparada ou pintada.
import 'models.dart';

/// Um complemento sugerido para uma peça principal.
class Complement {
  final String name;
  final double hours;
  final LaborType laborType;

  /// R&I (remoção e instalação). Quando falso, é troca (peça/material novo).
  final bool removeInstall;

  /// Também precisa sair quando a peça principal é só reparada/pintada.
  final bool forPaint;

  /// Vem marcado quando a peça principal é trocada.
  final bool onReplace;

  const Complement(
    this.name,
    this.hours, {
    this.laborType = LaborType.funilaria,
    this.removeInstall = true,
    this.forPaint = false,
    this.onReplace = true,
  });

  BudgetItem toItem(String parentId) => BudgetItem(
        description: name,
        op: removeInstall ? ItemOp.reparo : ItemOp.troca,
        removeInstall: removeInstall,
        laborHours: hours,
        laborType: laborType,
        parentId: parentId,
      );
}

const _el = LaborType.eletrica;
const _vd = LaborType.vidracaria;
const _tp = LaborType.tapecaria;
const _mc = LaborType.mecanica;

/// Grupo de peças: palavras que identificam a peça e seus complementos.
class PartGroup {
  final String id;
  final String label;
  final bool Function(String text) matches;
  final List<Complement> complements;
  const PartGroup(this.id, this.label, this.matches, this.complements);
}

bool _has(String t, List<String> any) => any.any(t.contains);

final partGroups = <PartGroup>[
  PartGroup('tampa', 'Tampa traseira / porta-malas',
      (t) => _has(t, ['tampa tras', 'porta malas', 'tampa do porta', 'tampa da mala']), [
    Complement('Lanterna da tampa', 0.3, laborType: _el, forPaint: true),
    Complement('Luz e suporte de placa', 0.2, laborType: _el, forPaint: true),
    Complement('Emblemas e logotipos', 0.2, forPaint: true),
    Complement('Fechadura e cilindro da tampa', 0.3),
    Complement('Amortecedores da tampa', 0.2),
    Complement('Forro da tampa', 0.3, laborType: _tp),
    Complement('Chicote elétrico da tampa', 0.4, laborType: _el),
    Complement('Limpador traseiro (motor e braço)', 0.3, laborType: _el),
    Complement('Aerofólio / spoiler', 0.3, forPaint: true),
    Complement('Borracha de vedação da tampa', 0.3),
    Complement('Vidro traseiro', 1.0, laborType: _vd),
  ]),
  PartGroup('porta_t', 'Porta traseira',
      (t) => t.contains('porta') && _has(t, ['tras']), [
    Complement('Forro da porta', 0.5, laborType: _tp, forPaint: true),
    Complement('Vidro da porta', 0.5, laborType: _vd),
    Complement('Vidro fixo / quebra-vento', 0.3, laborType: _vd),
    Complement('Máquina de vidro', 0.5, laborType: _el),
    Complement('Canaleta do vidro', 0.3),
    Complement('Fechadura da porta', 0.3),
    Complement('Maçaneta externa', 0.2, forPaint: true),
    Complement('Maçaneta interna', 0.1),
    Complement('Chicote elétrico da porta', 0.5, laborType: _el),
    Complement('Borracha de vedação da porta', 0.3),
    Complement('Friso / moldura externa', 0.2, forPaint: true),
    Complement('Alto-falante', 0.2, laborType: _el),
    Complement('Alinhamento e regulagem da porta', 0.5),
  ]),
  PartGroup('porta_d', 'Porta dianteira', (t) => t.contains('porta'), [
    Complement('Forro da porta', 0.5, laborType: _tp, forPaint: true),
    Complement('Vidro da porta', 0.5, laborType: _vd),
    Complement('Máquina de vidro', 0.5, laborType: _el),
    Complement('Canaleta do vidro', 0.3),
    Complement('Fechadura da porta', 0.3),
    Complement('Maçaneta externa', 0.2, forPaint: true),
    Complement('Maçaneta interna', 0.1),
    Complement('Retrovisor externo', 0.3, laborType: _el, forPaint: true),
    Complement('Chicote elétrico da porta', 0.5, laborType: _el),
    Complement('Borracha de vedação da porta', 0.3),
    Complement('Friso / moldura externa', 0.2, forPaint: true),
    Complement('Alto-falante', 0.2, laborType: _el),
    Complement('Alinhamento e regulagem da porta', 0.5),
  ]),
  PartGroup('capo', 'Capô', (t) => t.contains('capo'), [
    Complement('Borracha de vedação do capô', 0.2),
    Complement('Manta / isolamento térmico', 0.2),
    Complement('Emblema do capô', 0.1, forPaint: true),
    Complement('Esguichos e mangueira do lavador', 0.2),
    Complement('Dobradiças do capô', 0.3),
    Complement('Fechadura e cabo do capô', 0.3),
    Complement('Haste de sustentação', 0.1),
  ]),
  PartGroup('pc_d', 'Para-choque dianteiro',
      (t) => _has(t, ['para choque', 'parachoque']) && t.contains('diant'), [
    Complement('Grade do para-choque', 0.3),
    Complement('Faróis de neblina', 0.3, laborType: _el),
    Complement('Suportes / guias laterais', 0.3),
    Complement('Alma / absorvedor de impacto', 0.3),
    Complement('Sensores de estacionamento', 0.3, laborType: _el, forPaint: true),
    Complement('Placa e suporte de placa', 0.1, forPaint: true),
    Complement('Spoiler / defletor inferior', 0.2),
  ]),
  PartGroup('pc_t', 'Para-choque traseiro',
      (t) => _has(t, ['para choque', 'parachoque']) && t.contains('tras'), [
    Complement('Sensores de estacionamento', 0.3, laborType: _el, forPaint: true),
    Complement('Câmera de ré', 0.3, laborType: _el, forPaint: true),
    Complement('Refletores / lanterna de neblina', 0.2, laborType: _el),
    Complement('Suportes laterais', 0.3),
    Complement('Alma / absorvedor de impacto', 0.3),
    Complement('Luz e suporte de placa', 0.2, laborType: _el, forPaint: true),
  ]),
  PartGroup('paralama', 'Para-lama dianteiro',
      (t) => _has(t, ['para lama', 'paralama']), [
    Complement('Para-barro (caixa de roda)', 0.3),
    Complement('Pisca lateral (repetidor)', 0.1, laborType: _el, forPaint: true),
    Complement('Moldura / alargador da caixa de roda', 0.2, forPaint: true),
    Complement('Farol', 0.3, laborType: _el, forPaint: true),
    Complement('Para-choque dianteiro', 0.5, forPaint: true),
    Complement('Antena', 0.2, laborType: _el, onReplace: false),
  ]),
  PartGroup('lateral', 'Lateral traseira',
      (t) => t.contains('lateral') || (t.contains('caixa de roda') && t.contains('tras')), [
    Complement('Lanterna traseira', 0.3, laborType: _el, forPaint: true),
    Complement('Para-choque traseiro', 0.5, forPaint: true),
    Complement('Para-barro traseiro', 0.3),
    Complement('Vidro lateral traseiro', 1.0, laborType: _vd),
    Complement('Acabamento interno da lateral', 0.8, laborType: _tp),
    Complement('Banco traseiro', 0.5, laborType: _tp),
    Complement('Portinhola do tanque', 0.3, forPaint: true),
    Complement('Borracha de vedação da porta', 0.3),
  ]),
  PartGroup('teto', 'Teto', (t) => t.contains('teto'), [
    Complement('Forro do teto', 1.5, laborType: _tp),
    Complement('Para-brisa', 1.0, laborType: _vd),
    Complement('Vidro traseiro', 1.0, laborType: _vd),
    Complement('Antena', 0.2, laborType: _el, forPaint: true),
    Complement('Rack / longarinas', 0.3, forPaint: true),
    Complement('Luz de cortesia', 0.1, laborType: _el),
    Complement('Borrachas das portas', 0.4),
  ]),
  PartGroup('farol', 'Farol',
      (t) => t.contains('farol') && !t.contains('neblina'), [
    Complement('Lâmpadas do farol', 0.1, laborType: _el),
    Complement('Regulagem do facho do farol', 0.3, laborType: _el),
    Complement('Para-choque dianteiro', 0.5),
    Complement('Grade do radiador', 0.3),
  ]),
  PartGroup('lanterna', 'Lanterna traseira', (t) => t.contains('lanterna'), [
    Complement('Lâmpadas e soquetes', 0.1, laborType: _el),
    Complement('Acabamento interno do porta-malas', 0.3, laborType: _tp),
  ]),
  PartGroup('retrovisor', 'Retrovisor externo',
      (t) => t.contains('retrovisor') && !t.contains('interno'), [
    Complement('Forro da porta', 0.5, laborType: _tp),
    Complement('Chicote do retrovisor', 0.2, laborType: _el),
    Complement('Pisca do retrovisor', 0.1, laborType: _el, onReplace: false),
  ]),
  PartGroup('parabrisa', 'Para-brisa',
      (t) => _has(t, ['para brisa', 'parabrisa']), [
    Complement('Palhetas e braços do limpador', 0.2),
    Complement('Retrovisor interno', 0.1),
    Complement('Sensor de chuva / câmera', 0.3, laborType: _el),
    Complement('Grade do auvent (churrasqueira)', 0.3),
    Complement('Borracha / moldura do para-brisa', 0, removeInstall: false),
    Complement('Kit de colagem (cola PU)', 0, removeInstall: false),
  ]),
  PartGroup('vidro_t', 'Vidro traseiro',
      (t) => t.contains('vidro') && t.contains('tras'), [
    Complement('Conexões do desembaçador', 0.2, laborType: _el),
    Complement('Brake light (luz de freio alta)', 0.2, laborType: _el),
    Complement('Limpador traseiro', 0.2, laborType: _el),
    Complement('Kit de colagem (cola PU)', 0, removeInstall: false),
  ]),
  PartGroup('grade', 'Grade do radiador', (t) => t.contains('grade'), [
    Complement('Emblema da grade', 0.1),
  ]),
  PartGroup('radiador', 'Radiador', (t) => t.contains('radiador'), [
    Complement('Ventoinha', 0.5, laborType: _mc),
    Complement('Mangueiras do radiador', 0.3, laborType: _mc),
    Complement('Para-choque dianteiro', 0.5),
    Complement('Fluido de arrefecimento', 0, removeInstall: false),
  ]),
  PartGroup('painel', 'Painel frontal',
      (t) => _has(t, ['painel frontal', 'painel dianteiro', 'frente do carro']), [
    Complement('Radiador', 1.0, laborType: _mc),
    Complement('Condensador do ar-condicionado', 0.5, laborType: _mc),
    Complement('Ventoinha', 0.5, laborType: _mc),
    Complement('Faróis', 0.6, laborType: _el),
    Complement('Para-choque dianteiro', 0.5),
    Complement('Fechadura e cabo do capô', 0.3),
    Complement('Carga de gás do ar-condicionado', 0, removeInstall: false),
  ]),
  PartGroup('soleira', 'Soleira / caixa de ar',
      (t) => _has(t, ['soleira', 'caixa de ar', 'longarina']), [
    Complement('Borrachas das portas', 0.4),
    Complement('Acabamento interno da soleira', 0.3, laborType: _tp),
    Complement('Banco dianteiro', 0.5, laborType: _tp),
  ]),
];

String normalizePart(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : (ch == '-' || ch == '/' ? ' ' : ch));
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Grupo da peça principal (ou nulo se não houver complementos cadastrados).
PartGroup? groupFor(String description) {
  final t = normalizePart(description);
  if (t.isEmpty) return null;
  for (final g in partGroups) {
    if (g.matches(t)) return g;
  }
  return null;
}

/// Complementos sugeridos para uma peça, com quais vêm marcados.
List<(Complement, bool)> complementsFor(BudgetItem parent) {
  if (parent.op == ItemOp.servico || parent.parentId.isNotEmpty) return [];
  final g = groupFor(parent.description);
  if (g == null) return [];
  final replacing = parent.op == ItemOp.troca;
  return [
    for (final c in g.complements)
      (c, replacing ? c.onReplace : c.forPaint),
  ];
}

/// Mantém cada complemento logo abaixo da sua peça principal.
List<BudgetItem> groupChildren(List<BudgetItem> items) {
  final ids = {for (final it in items) it.id};
  for (final it in items) {
    if (it.parentId.isNotEmpty && !ids.contains(it.parentId)) it.parentId = '';
  }
  final out = <BudgetItem>[];
  for (final it in items) {
    if (it.parentId.isNotEmpty) continue;
    out.add(it);
    out.addAll(items.where((c) => c.parentId == it.id));
  }
  return out;
}

/// Complementos já lançados para a peça.
List<BudgetItem> childrenOf(List<BudgetItem> items, BudgetItem parent) =>
    items.where((c) => c.parentId == parent.id).toList();
